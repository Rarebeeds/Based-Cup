# BASED CUP — Project Handoff

A browser-based, 2-player **online soccer game** (Pepe vs Trumpe). Top-down HTML5
canvas, one self-contained `index.html`, a tiny WebSocket relay, a Supabase backend,
and Vercel hosting. This document is everything needed to continue development.

**Current build: `b24`** (shown bottom-right in-game as `build: based-cup b24 ✓`).

---

## 1. How to work on this (dev workflow)

The **source of truth is `game_template.html`** — edit that, never `index.html` directly.
It contains tokens `__PEPE__` / `__TRUMPE__` where the base64 sprites get injected at
build time (keeps the source small and editable).

```
# 1. edit game_template.html
# 2. build:
python3 build.py                # -> writes index.html + check.js + ids.json
# 3. validate:
node --check check.js           # syntax check (must pass)
node harness.cjs                # load-time + "missing element" check (see §6)
# 4. deploy the game:
#    upload index.html to your GitHub repo root -> Vercel auto-deploys
```

**Always bump the version badge** when you change something, so you can confirm the
live site updated. In `game_template.html` search for `build: based-cup b24` and
increment it (e.g. `b25`). The badge is the canonical "is the new build live?" check —
hard-refresh (Ctrl+Shift+R) if the browser shows an old number.

> Tip for Claude Code: open this folder, then say *"Read HANDOFF.md — this is Based Cup,
> a token-built single-file HTML game. Edit game_template.html, run build.py, then
> node --check and node harness.cjs before we ship."*

---

## 2. Architecture

| Piece | Tech | Where it lives |
|---|---|---|
| Game client | HTML5 canvas + vanilla JS, single file | `index.html` on **Vercel** (repo root) |
| Leaderboard API | Vercel serverless functions | `api/result.js`, `api/leaderboard.js` |
| Accounts / profiles / friends / chat / leaderboard data | **Supabase** (Postgres + Auth + Realtime) | cloud |
| Lobby relay + quick-match matchmaking | zero-dep Node WebSocket server | **Fly.io**, Sydney region |

Online play is **host-authoritative**: the host's browser simulates the match and
streams ~40Hz snapshots; the guest streams input ~33Hz and renders interpolated
snapshots with local prediction of its own player. The relay just pairs players and
forwards messages — it does **not** run the game.

---

## 3. Infrastructure — URLs, keys, accounts

- **Supabase**
  - `SUPA_URL = https://mnwnuwdthjksioqsyooj.supabase.co`
  - Anon key is baked into the client (role `anon`, safe to ship).
  - **Email confirmation must be OFF** (Auth settings) or new sign-ups can't get a
    session and profiles won't be created.
  - ⚠️ **The `service_role` key was partially exposed earlier in chat — ROTATE IT** in
    the Supabase dashboard if you haven't. Never put service_role in client code.
- **Fly.io lobby**
  - App: `basedcup-lobby-syd` · URL: `wss://basedcup-lobby-syd.fly.dev` · region `syd`
  - Always-on (`min_machines_running = 1`, `auto_stop_machines = false`) ≈ US$2/mo.
  - **MUST run exactly ONE machine.** The matchmaking queue is in-memory; two machines
    split the queue and quick-match silently fails. Check + fix:
    `fly status`  →  `fly scale count 1`
  - Deploy after server edits: from the lobby folder, `fly deploy`.
- **Vercel** — hosts the game + the leaderboard API. Auto-deploys on GitHub push.
- **GitHub** — your repo is the deployed source of truth for `index.html` + `api/`.

---

## 4. Files in this package

```
based-cup/
├── HANDOFF.md                 <- this file
├── game_template.html         <- SOURCE (edit this)
├── pepe_cut_s.png             <- sprite (380x340) injected as __PEPE__
├── trumpe_cut_s.png           <- sprite (309x340) injected as __TRUMPE__
├── build.py                   <- builds index.html from the template + sprites
├── harness.cjs                <- node sandbox load-check (catches missing-element bugs)
├── index.html                 <- the current built b21 (deployable; Vercel repo root)
├── lobby/                     <- the Fly.io relay + matchmaking server
│   ├── server.js              <- relay + quick-match queue
│   ├── package.json
│   ├── Dockerfile
│   ├── fly.toml               <- Sydney, always-on
│   ├── fly-singapore.toml     <- optional 2nd region (NOT deployed)
│   ├── DEPLOY.md
│   └── SINGAPORE-DEPLOY.md
├── vercel-api/                <- copy these into your repo's /api folder
│   ├── result.js              <- POST match result -> Supabase
│   └── leaderboard.js         <- GET ranked leaderboard
├── sql/                       <- run in Supabase SQL editor, IN ORDER
│   ├── social-schema.sql      <- profiles, friendships, messages + RLS + RPCs
│   ├── social-schema-add.sql  <- avatar column + name/avatar lookups
│   ├── social-schema-add2.sql <- wins/losses, public_profile, comments
│   ├── social-schema-add3.sql <- remove_friend, xp column
│   ├── social-schema-add4.sql <- guest counter (bump_counter/get_counter) for "goy" names
│   └── social-schema-add5.sql <- $BASED coins column + locked write grants + settle_match() wager RPC
└── x-assets/                  <- social kit
    ├── x_profile.png          <- 400x400 avatar
    ├── x_banner.png           <- 1500x500 header
    └── x_brand.md             <- bio + announcement post copy
```

If you set up the Supabase project from scratch, run the six `sql/` files in order.
On your existing project, `add5` ($BASED coins + wagering) is the **newest and must be
run** in the Supabase SQL editor or coins/wagers won't work (the client expects a
`coins` column and a `settle_match` RPC). It also revokes direct client writes to the
`coins` column so balances can only change through `settle_match()` — don't undo that.

---

## 5. Current feature set (what's built)

- **Title screen**: cinematic night-stadium scene with a looping Looney-Tunes chase —
  one character dribbles, the other chases, direction + roles flip each lap. Animated
  "slam-in" title, procedural theme music (intro) and calm lobby music. 🔇 mute button.
- **Modes**: Quick Match (online matchmaking, ranked, CPU fallback removed — keeps
  searching), Practice (vs CPU / local 2-player / solo), Play a Friend (online lobby
  by code or invite link or friend challenge).
- **Game modes**: ⚽ Goals or ⏱️ Keep-Away (hold the ball longest), selectable for
  quick match and friend matches.
- **Two halves**: each match is two 1-minute halves with a **5-second frozen HALF-TIME
  break** (dedicated countdown screen; the pitch freezes and resumes from the same
  positions — host-authoritative, synced to the guest via the `ht` snapshot flag).
- **Main menu**: a single **▶ PLAY** hub opens a mode picker — 💰 Wager Mode (matchmaking
  with a $BASED stake), ⚡ Quick Match (matchmaking, no wager), 🎮 Play a Friend (private
  lobby). Wagering is exclusive to Wager Mode (Quick/Friend force stake 0 — no overlap).
  A 🛒 **STORE** button opens a currency-top-up screen (placeholder — "coming soon", no
  marketplace yet). An **𝕏 link** (top-right by the bell) opens https://x.com/BasedCup1.
- **Netcode**: host-authoritative, tuned for the Sydney link (INTERP_DELAY 68ms,
  BALL_DELAY 22ms, host 40Hz, guest input 33Hz). Live ping readout during online play.
- **Accounts**: local (device) + Supabase (cross-device). Register with Solana address
  + username + 4-digit PIN. **Connect Phantom** auto-fills the address. **Play as Guest**
  ("goy"+global count, no wallet) with a prompt to add a wallet for the giveaway.
- **Social**: friends (search/request/accept/remove), live chat, public profiles with
  avatars + comments, own profile (avatar upload, stats, achievements), notifications
  (unread messages, comments, friend requests, challenges).
- **Progression**: XP/levels, 10 achievements, global ranked leaderboard.
- **$BASED coins (in-game currency)**: signed-in accounts start at 1000 🪙, mirrored to
  Supabase like XP. Earn a small faucet (+10 win / +5 loss) per online match, or **wager**
  on quick/friend matches (host picks 0/50/100/250; winner takes the pot). Shown on the
  account button + profile. **Guests are casual-only**: a guest never exchanges a
  settlement id and never calls `settle_match`, so any match involving a guest moves
  **zero** coins for either side (no wager, no faucet). To earn coins you must play
  another signed-in account.
  - **Settlement is dual-confirmation:** both peers report their result to `settle_match()`
    and coins only move when both agree on the same match, so a cheating host can't mint a
    win and a fake/solo match can't farm the faucet. Coins are off-chain bragging-rights
    points (NOT real SOL). **Known v1 limit:** a *losing* player can rage-quit before
    confirming to void the pot (nobody loses coins, but the winner isn't paid) — acceptable
    for now; add forfeit-on-disconnect later if it's abused.
- **Regions**: 🇦🇺 Sydney (live) / 🇸🇬 Singapore (config present, not deployed).

---

## 6. The harness (run this before every ship)

`node harness.cjs` loads the built script in a sandbox and reports:
- **load-time throws** (syntax is caught by `node --check`, but runtime ReferenceErrors
  at top level aren't), and
- **wiring to elements that don't exist** — e.g. `$('quickBtn').onclick=...` when
  `quickBtn` isn't in the HTML. That throws `null.onclick` and silently kills ALL
  button wiring after it (this exact bug shipped once and broke the whole game). The
  harness uses `ids.json` (the real element ids) to catch it. **Always run it.**

---

## 7. What's NOT done / next steps

- **Hourly 0.1 SOL payout** — the in-game banner collects wallets, but nothing sends
  SOL. You need a separate backend job: a funded sending wallet + a scheduler (cron)
  that reads the Supabase leaderboard, picks the winner, and signs/sends with
  `@solana/web3.js`. The sending key must live server-side only, never in the client.
- **Singapore relay** — `lobby/fly-singapore.toml` is ready; deploy only if you get
  players in Asia (`fly apps create basedcup-lobby-sin` then `fly deploy -c fly-singapore.toml`).
- **Matchmaking** is a single in-memory FIFO queue (no skill rating, one region). Fine
  for now; revisit if you get real volume.
- **Promo**: post the announcement (x-assets/x_brand.md), grab a gameplay clip.

---

## 8. Gotchas / hard-won lessons

- **Quick match drops to "searching" forever / used to fall to CPU** → usually TWO Fly
  machines. `fly scale count 1`.
- **Whole game won't start / buttons dead** → something wired to a missing element id.
  Run `node harness.cjs`.
- **Music doesn't play** → browsers block autoplay; it starts on the first tap/click.
- **Connect Phantom does nothing** → only works with the Phantom browser extension or
  inside the Phantom app's in-app browser; a plain mobile browser has no provider.
- **Guests can't receive prizes** → by design (no wallet); they add one via the banner.
- **"New build not live"** → browser cache. Hard-refresh; confirm the bottom-right
  version badge matches the build you shipped.
- **Running `node server.js` locally is NOT deploying** → only `fly deploy` updates the
  live relay.
- **Sprites bleed to their PNG edges** → don't add edge-traced glows (shadowBlur) to
  them or you get hard "cropping" lines; use a soft radial halo behind instead (already
  done in `drawHero`).
- **`python build.py` crashes on Windows with a `UnicodeDecodeError` (cp1252)** → fixed:
  `build.py` now reads/writes with `encoding='utf-8'` because the template contains emoji.
  If you re-clone an old copy, re-apply that or run with `PYTHONUTF8=1`.
- **Coins don't move / "settle_match does not exist"** → you haven't run
  `sql/social-schema-add5.sql` in Supabase. Coins/wagers need it.
- **Wager Mode and Quick Match share ONE matchmaking queue** → the Fly relay has a single
  in-memory FIFO (`t:'quick'`), so a Wager-Mode player can be paired with a Quick-Match
  player. That's safe (coins only move when BOTH picked a stake>0 — a quick player staked
  0, so the handshake settles to a friendly 0 wager), but it means Wager Mode isn't
  *guaranteed* to find another staker. Separating them needs a second server queue (a
  `lobby/server.js` change + `fly deploy`). Left shared for now to avoid a relay redeploy.
- **Wager always shows "void"** → the two peers reported different stakes (one couldn't
  afford it, or quick-match players picked different amounts → the lower of the two is used,
  and if either can't cover it the wager voids with no coins moved). The +5/+10 faucet still
  pays. This is the safe-by-design path, not a bug.

---

## 9. Quick reference — common commands

```
# build + validate the game
python3 build.py && node --check check.js && node harness.cjs

# deploy the relay (from lobby/)
fly deploy
fly status                 # confirm region syd + exactly 1 machine
fly scale count 1          # if 2 machines appear
fly logs                   # startup line should mention "+ matchmaking"

# the relay health check
# open https://basedcup-lobby-syd.fly.dev  -> should say "lobby ok"
```
