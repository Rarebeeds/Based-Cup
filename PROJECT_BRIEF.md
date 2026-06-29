# PROJECT_BRIEF.md — Based Cup (full technical + design brief, current to b50)

The comprehensive "how this game is built and where it's at" doc. Paste into the planning chat to seed it;
Claude Code can also read it. For the lean per-session save file use **STATE.md**; for the rules use **CLAUDE.md**.
This supersedes anything stale in the original **HANDOFF.md** (which is read-only and predates the newer systems).

---

## 1. What it is
**Based Cup** — a browser, real-time **2-player online soccer** game, "head soccer" style (the players are big
heads). Meme characters (Pepe, Trumpe, wojaks, etc.). Free to play; a $BASED in-game currency + optional SOL
giveaway funds engagement but the game is the point.

**North-star constraints (sacred):**
- **Fairness is visible and equal.** Every character has an IDENTICAL hit/control box (`grabCap`); only
  speed/power/stamina differ (character identity), and stat totals are balanced (~21). No secret advantages.
- **One source of truth** for every money/config number (coins via Supabase RPC, etc.).
- Plays cleanly on **mobile** (it's where most users are).

## 2. Architecture in one sentence
The **entire game is one self-contained HTML file**. `game_template.html` is the source (with `__TOKEN__`
placeholders for big assets); `build.py` injects the base64 sprites + intro image and writes the deployable
**`index.html`**. No framework, no bundler — vanilla JS + Canvas 2D.

## 3. Tech stack & hosting
- **Client:** single HTML file, vanilla JS, Canvas 2D. ~3,200 lines of source.
- **Build:** `build.py` (token injection) → `index.html` + `check.js` (extracted script for syntax check) + `ids.json`.
- **Host:** **Vercel** (static `index.html` + serverless `/api` for the leaderboard in `vercel-api/`).
- **Realtime relay:** **Fly.io** WebSocket relay (`lobby/server.js`), regions Sydney/Singapore/US. Single
  machine per region (in-memory matchmaking queue). `fly deploy` is manual (user does it).
- **Backend data:** **Supabase** (auth, profiles, friends, chat, coins via RPC, presence channels). Anon key + RLS.
- **Wallet:** Phantom (Solana) connect for the address; payouts are manual/human-in-the-loop (no hot wallet).

## 4. File / folder map
```
game_template.html   SOURCE of the whole game (edit this)
index.html           BUILT output (deploy THIS, never the template)
build.py             token-injection build (PEPE/TRUMPE/extra sprites + intro image + __EXTRA_CHARS__)
process_sprites.py   raw portrait -> normalised <key>_cut.png head sprite
harness.cjs          load-time + missing-element check
check.js / ids.json  build artifacts for validation
*_cut.png, *_cut_s.png  processed character sprites (injected at build)
intro_reveal.jpg     the one-time intro reveal image
lobby/server.js      Fly WebSocket relay + matchmaking
vercel-api/          serverless leaderboard (/api/leaderboard, /api/result)
sql/                 Supabase schema + RPCs (settle_match, my_friends, etc.)
CLAUDE.md/STATE.md   session memory (this workflow). HANDOFF.md = old read-only briefing.
```

## 5. Build / validate / deploy (the operational loop)
```
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
python build.py
node --check check.js
node harness.cjs
```
Then: audit `index.html` for leftover `__[A-Z_]+__` tokens (must be 0), confirm 0 placeholder sprites, **bump
the badge** (`based-cup bNN ✓` in game_template.html). User uploads `index.html` → Vercel. ⚠️ **Deploying the
TEMPLATE instead of index.html is the #1 footgun** — `__EXTRA_CHARS__` is a bare identifier and throws, killing
the whole script ("game won't start"). That's what b50's guard + the on-screen error reporter defend against.

## 6. How the client code is organised (inside game_template.html)
One big `<script>`, roughly in this order:
- **Error reporter** (very top): catches uncaught errors → red bar + 📋 COPY ERRORS button.
- **Config/constants:** field size (1060×650), `PLAYER_R`, `BALL_R`, head-soccer face constants
  (`FACE_RF/FACE_CYF/FACE_FIT/CHIN_FRAC_DRAW`), `STATS{}` (per-char), `SP_SCALE{}`, sprite `IMG{}` map.
- **Game state:** `state` machine (`menu`/`play`/`paused`/`win`), `players{p,t}`, `ball`, `score`, modes.
- **Input:** keyboard + mouse (desktop) and a one-finger joystick + KICK + rim-sprint (touch).
- **Audio:** fully synthesised (WebAudio) — sfx + procedural music, no files.
- **Physics/gameplay:** `applyMove`, `chargeKick`/`tryKick` (power from charge+stat only, never speed),
  `updatePossession` + `grabCap` (identical for all), `glueBall` dribble, walls/corners/nets, goals,
  keep-away mode + rebound bonus, half-time.
- **AI:** `aiControl` (easy/normal/hard) — chases ball / dribbles to goal / flees in keep-away.
- **Rendering:** `draw()` → pitch + `drawBall` + `drawPlayer` + aim arrows; `drawTitleScene`/`drawHero`
  for the splash chase animation. **drawPlayer is "head soccer":** no hitbox ring, head face-centred on the
  player, sized so the face edge ≈ the invisible collision; team shown by a soft coloured ground pool.
  Draw constants: `FACE_RF=0.278, FACE_CYF=0.62, FACE_FIT=1.15, CHIN_FRAC_DRAW=0.84` (knobs if heads look
  off: `FACE_FIT` size, `FACE_CYF` vertical position). `SP_SCALE{}` still exists but drawPlayer no longer uses it for size.
- **Loop:** `loop(ts)` — guest streams input + interpolates; host simulates + streams snapshots; then `draw()`.
- **Accounts/auth, social, economy, leaderboard, profile, daily/XP/achievements** (Supabase-backed, big section).
- **Online netcode** (`NET` object) + matchmaking + wager handshake.
- **Flow/wiring** at the bottom: button handlers, `showLoadingThen`/`showIntroLoading`, `enterMatchChrome`,
  `gotoMenu`, then `requestAnimationFrame(loop)`.

## 7. Sprite pipeline (process_sprites.py) — "molded to one style"
- Input: raw portrait `<key>.png` (solid bg). Output: `<key>_cut.png` (pepe/trumpe → `_cut_s.png`).
- **Background removal:** edge flood-fill, `THRESH3=110` — deliberately BELOW pale-skin colour distance (~150)
  so white/pale wojak faces survive (at 200 they got eaten → invisible characters). If a face goes invisible, that's the knob.
- **Face normalisation:** measure the face (width + chin), then scale every character so the **face is one width**,
  **chin anchored to a fixed line**, centred on a fixed **360×450 frame**. So in-game all heads are the same size with
  chins/eye-lines aligned. Per-char `ADJUST` nudges fix a few the auto-measure misreads (boomer/okeyjak/pdidpe).
- Then build.py injects `<key>_cut.png` as base64; only characters whose `_cut.png` exists become selectable (`__EXTRA_CHARS__`).
- ⚠️ OneDrive churns files in this folder (dehydrates/moves them). Backups of `_cut` sprites are kept in the session scratchpad.

## 8. Netcode (host-authoritative + optional P2P)
- Host simulates everything, streams ~60Hz snapshots; guest streams input ~55Hz, interpolates the world in the
  past, predicts its OWN player for instant feel. **Guest is always the right-side player (`players.t`).**
- **Transport:** `NET.ws` (Fly relay — always on: matchmaking, signalling, reliable control) + optional
  `NET.dc` (**WebRTC P2P** DataChannel, unreliable, STUN-only — ~halves RTT). Host offers / guest answers;
  signalling rides the relay as `{rtc:…}`. **Routing rule:** only `state|input|ping|pong` go over P2P
  (loss-tolerant); control (`start/hello/wagerAck/rematch/left`) MUST stay reliable on the WS. Auto-fallback to relay. `⚡`=P2P.
- **Interpolation:** adaptive buffers from measured ping — `INTERP_DELAY=clamp(34+rtt*0.30,44,140)`,
  `BALL_DELAY=clamp(16+rtt*0.10,20,54)`. Snapshots rounded to shrink frames. Opponent-dribbled ball is glued to
  their delay (fixes a "rubber-band leash").
- **Two ping numbers:** server-picker = warmed HTTPS fetch (handshake used to inflate it ~3×); in-match pill =
  your RTT + opponent's RTT to the region (two AU players ≈ 60ms is normal/expected).

## 9. Design decisions worth remembering (the "why")
- **Hitbox equal for all** — fairness is the brand; never trade it for a "cooler" character.
- **Kick power from charge + power-stat only**, never player velocity (so movement can't be exploited into shot power).
- **No visible hitbox ring** (b47) — pure heads; team read via a soft coloured ground pool.
- **One-time intro** (terminal type → curtain rise → reveal image) only on the first START of a session; tap-to-skip + safety timer so it can't trap anyone.
- **Mobile-first chrome:** one-finger joystick (`#joy`, bound to a finger by id), rim-push = sprint, aim follows the joystick (mouse doesn't exist on touch — that fixed the "stuck arrow" bug), KICK = `#kickBtn`. `body.touch-match` moves player cards to the TOP so thumbs own the bottom; overlays scroll (`overflow-y:auto`, `touch-action:pan-y`); `viewport-fit=cover`; rotate-your-phone nudge in portrait-during-play.
- **Diagnose before fixing** — the on-screen error reporter exists because device-specific bugs don't reproduce on desktop.

## 10. Current state (b50)
14 characters (see STATE.md table). All core systems built & working: online play (relay + P2P), accounts/guest,
$BASED + wager, friends/chat/inbox, leaderboard, daily/XP/achievements, profiles, region picker, live counter,
mobile controls, intro. Build validated; 0 leftover tokens; error reporter live.

## 11. Roadmap / deferred (next candidates)
- **TURN server** so P2P works through strict/mobile (CGNAT) NATs (currently STUN-only → those fall back to relay). Biggest latency win.
- **4-player (2v2)** in one match — requested, NOT built. Needs rooms-of-4 in server.js (+fly redeploy), 2v2
  teams + 4-player render/collision, binary/delta snapshot encoding (~6× bandwidth), star-topology P2P. Multi-phase; defer-don't-half-build.
- More characters available in `SOCC\CHARACTERS` to add on request.

## 12. Known gotchas (the landmines)
- Deploy `index.html`, never `game_template.html`. Audit 0 leftover tokens after build.
- OneDrive dehydrates/moves files in this folder mid-session — verify sprites/build.py exist before building.
- Windows hides extensions → saved `foo.png` becomes `foo.png.png`; rename before processing.
- The relay must stay a single machine per region (in-memory queue); `auto_stop_machines=false`, `min_machines_running=1`.
- Supabase needs email-confirm OFF; coins/wager settle via the `settle_match` RPC (record-first, notify-second).
- `python build.py` once crashed on Windows with `UnicodeDecodeError` (cp1252) because the template has emoji — build.py now reads/writes `encoding='utf-8'`. Re-apply (or `PYTHONUTF8=1`) if an old copy is re-cloned.
- Music won't autoplay — browsers block it; it starts on the first tap/click. Connect Phantom only works with the Phantom extension or the Phantom in-app browser (a plain mobile browser has no provider).
- `node server.js` locally is NOT a deploy — only `fly deploy` updates the live relay. Sprites bleed to their PNG edges → never add edge-traced glows (`shadowBlur`); use a soft radial halo behind (as in `drawHero`).
- Wager "void" is usually by design: the two peers reported different stakes (lower of the two is used; if either can't cover it the wager voids, no coins move). The +5/+10 faucet still pays. Settlement is dual-confirmation (both peers report to `settle_match`); **v1 limit:** a losing player can rage-quit before confirming to void the pot (winner unpaid, nobody loses) — add forfeit-on-disconnect later if abused.

## 13. Infrastructure reference (identifiers, secrets, SQL run-order)
- **Supabase:** `SUPA_URL = https://mnwnuwdthjksioqsyooj.supabase.co`. Anon key (role `anon`) is baked into the client — safe to ship. **Email confirmation must be OFF** or sign-ups can't get a session/profile. ⚠️ The `service_role` key was partially exposed in chat earlier — **rotate it** in the dashboard if not already; never put service_role in client code.
- **`sql/` files — run IN ORDER** in the Supabase SQL editor (each builds on the last):
  `social-schema.sql` (profiles, friendships, messages, RLS, RPCs) → `…-add.sql` (avatar + lookups) → `…-add2.sql` (wins/losses, public_profile, comments) → `…-add3.sql` (remove_friend, xp) → `…-add4.sql` (guest counter for "goy" names) → `…-add5.sql` ($BASED coins column + locked write grants + `settle_match()` wager RPC). **add5 is newest and required** — coins/wagers break without it, and it revokes direct client writes so balances only change via `settle_match()` (don't undo that).
- **Fly relay:** app `basedcup-lobby-syd` · `wss://basedcup-lobby-syd.fly.dev` · region `syd` · always-on (`min_machines_running=1`, `auto_stop_machines=false`, ≈US$2/mo). Health check: open `https://basedcup-lobby-syd.fly.dev` → should say "lobby ok". Singapore config (`lobby/fly-singapore.toml`) is present but **not deployed** (`fly apps create basedcup-lobby-sin` then `fly deploy -c fly-singapore.toml` if Asia players appear).
- **Vercel API:** `vercel-api/result.js` (POST match result → Supabase) + `vercel-api/leaderboard.js` (GET ranked). Copy into the repo's `/api` folder; auto-deploys on GitHub push.
- **Promo / brand:** `x-assets/` (x_profile.png 400×400, x_banner.png 1500×500, x_brand.md bio + announcement copy). Account: https://x.com/BasedCup1.
- **Deferred (no backend yet):** the hourly 0.1 SOL payout — the banner collects wallets but nothing sends SOL; needs a server-side funded wallet + cron that reads the leaderboard and signs with `@solana/web3.js` (key server-side only, never client).
