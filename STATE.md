# STATE.md — Based Cup living state log

Read **CLAUDE.md** first (laws/build/deploy). Deep internals are in **PROJECT_BRIEF.md**. This file = current state only.

> ## ⚠️ END-OF-SESSION RULE — update BEFORE you wrap (this is what stops cross-session drift)
> At every clean stopping point and always before ending a session, update this file:
> 1. **Current build number** (the `## Current build:` line below) — match the badge you bumped in `game_template.html`.
> 2. **Status table** — flip rows to their real status (done / in-flight / next) + build #.
> 3. **Log** — add a one-line `bNN:` entry for what changed + what's next.
>
> Then confirm the badge is bumped and `index.html` is built/validated. (Rules/gotchas change → update CLAUDE.md instead.)

## Current build: **b55** (badge in `game_template.html`, search `based-cup bNN ✓`)
Last verified: 6-stat model behaviorally tested in-browser (all 14 total 36, pace correct, on/off split active for human AND CPU, glue scales with dribble, steal-contest probability scales with defense−dribble gap); grabCap re-proven constant 48; kick power still charge+power only; 0 tokens, 0 placeholders, harness passes.
✅ **b55 = Phase 2 stat model** (per BASED_CUP_STAT_DESIGN.md). Old 3-stat (speed/power/stamina ~21) → 6 assignable stats (on-ball, off-ball, power, defense, dribble, stamina), every char totals **36**, lopsided spread = archetypes. Pace (display) = on+off. **Phase 3 (character menu) NOT built yet** — the old 3-bar select carousel got a 1-line compat shim so it doesn't render NaN. b54 AI tier logic untouched (it just reads the new stats via the shared movers).
This folder is the git checkout (branch `main` tracking `origin/main`); deploy = `git push origin main`.

### Stat-model tunable constants (b55) — names + current values (near the top of the script)
`STEAL_BASE=0.30` (even-match steal chance/contest), `STEAL_WEIGHT=0.06` (±chance per defense−dribble point), `STEAL_MIN=0.05`/`STEAL_MAX=0.85` (clamp), `STEAL_TRY_GAP=22`f (between contest attempts), `STEAL_COOLDOWN=40`f (grace after a steal). `DRIBBLE_GLUE_MIN=0.30`/`DRIBBLE_GLUE_MAX=0.55` (glueBall tightness from dribble 1..10; old fixed 0.40). `DEF_CLOSE_BONUS=0.06` (off-ball speed per defense point when chasing the carrier). Speed: `maxOn=4.2+onball*0.16`, `maxOff=4.2+offball*0.16`; `kickPow=9+power*0.9` (unchanged).
**Sprint/stamina resolution (flagged decision):** sprint stays a universal, stamina-gated `×SPRINT_MULT` multiplier applied on top of WHICHEVER base is active (on-ball base while possessing, off-ball otherwise). The split only swaps which base sprint multiplies; the stamina economy is unchanged. Closing-speed bonus is added flat (outside the sprint multiply) so it stays modest.

---

## Status board (read this first)
| Feature / system | Status | Build |
|------------------|--------|-------|
| Core gameplay (move/charge-kick/possession/goals/walls) | ✅ done | — |
| Hitbox equality (`grabCap` identical for all) | ✅ done · sacred | — |
| Head-soccer render (no ring, face-centred, team pool) | ✅ done | b47 |
| Face-normalised sprites (chin-aligned, consistent size) | ✅ done | b46 |
| 14-character roster | ✅ done | b43→b50 |
| Online netcode (host-authoritative, relay) | ✅ done | b40 |
| WebRTC P2P transport (STUN-only, ~halves RTT) | ✅ done | b39 |
| Accounts (local + Supabase), guest play, PIN auth | ✅ done | — |
| $BASED coins + wager mode (settle_match RPC) | ✅ done | — |
| Friends / chat / inbox (Supabase realtime) | ✅ done | — |
| Leaderboard (/api on Vercel, local fallback) | ✅ done | — |
| Daily tasks, XP/levels, achievements, profile + avatar | ✅ done | — |
| Server-region picker, live "playing now" counter | ✅ done | b38 |
| Phantom wallet connect, invite links | ✅ done | — |
| Keep-away mode + rebound bonus, half-time | ✅ done | — |
| Mobile controls + overlay scroll + rotate nudge | ✅ done | b41/b42 |
| One-time intro (terminal → curtain → reveal) | ✅ done | b44/b45 |
| On-screen error reporter (red bar + 📋 COPY) | ✅ done | b48/b49 |
| Input handlers robust to synthetic key events (autofill/extensions) | ✅ done | b53 |
| AI difficulty tiers (easy/normal/hard genuinely escalate) | ✅ done | b54 |
| 6-stat model (on/off speed, power, defense, dribble, stamina; total 36) | ✅ done | b55 |
| Steal-as-contest (defense vs dribbling, cooldown) + dribble glue | ✅ done | b55 |
| Character menu showing the 6 stats + pace (Phase 3) | 🔜 next — not built (old carousel shimmed) | — |
| Crash-proof `EXTRA_CHARS` guard (un-built can't dead-screen) | ✅ done | b50 |
| **TURN server** (P2P through CGNAT/mobile NATs) | 🔜 next — biggest latency win | — |
| **4-player (2v2)** in one match | 🔜 next — multi-phase, not started | — |
| Hourly 0.1 SOL payout backend | 🔜 deferred — banner collects wallets, nothing sends | — |
| More characters from `SOCC\CHARACTERS` | 🔜 on request | — |

---

## Roster (14 characters) — 6-stat model (b55), every char totals **36**
`grabCap()` identical for ALL (no hitbox advantage). `key` = internal id / sprite filename. ON=on-ball spd, OFF=off-ball spd, PWR=power, DEF=defense, DRB=dribble, STA=stamina; Pace=ON+OFF (display).

| key | name | ON | OFF | PWR | DEF | DRB | STA | Pace | archetype |
|-----|------|----|----|-----|-----|-----|-----|------|-----------|
| pepe | PEPE | 9 | 8 | 4 | 3 | 8 | 4 | 17 | Speedster-Dribbler (hero) |
| elon | MUSKPE | 8 | 10 | 5 | 3 | 5 | 5 | 18 | Pure Speedster |
| pdidpe | PDIDPE | 9 | 7 | 5 | 3 | 9 | 3 | 16 | Dribbler |
| obampe | OBAMPE | 7 | 7 | 6 | 6 | 5 | 5 | 14 | All-rounder (pace) |
| chad | CHAD | 7 | 6 | 9 | 4 | 5 | 5 | 13 | Power-pace hybrid |
| wojak | WOJAK | 6 | 6 | 6 | 6 | 6 | 6 | 12 | Pure All-rounder |
| okeyjak | OKEYJAK | 6 | 6 | 6 | 5 | 7 | 6 | 12 | All-rounder (dribble) |
| sadjak | SADJAK | 5 | 6 | 6 | 7 | 5 | 7 | 11 | All-rounder (defense) |
| doomer | DOOMJAK | 5 | 5 | 10 | 5 | 4 | 7 | 10 | Powerhouse |
| boomer | ALEX | 4 | 5 | 5 | 9 | 4 | 9 | 9 | Wall (stamina) |
| soyjak | SOYJAK | 4 | 5 | 9 | 7 | 4 | 7 | 9 | Power-Defense |
| trumpe | TRUMPE | 4 | 4 | 10 | 7 | 4 | 7 | 8 | Powerhouse |
| grandpa | EPPE | 3 | 4 | 7 | 10 | 3 | 9 | 7 | Wall (heavy) |
| oldwoj | OLDJAK | 3 | 4 | 9 | 9 | 3 | 8 | 7 | Defensive Powerhouse |

*(pepe/trumpe sprites are `pepe_cut_s.png`/`trumpe_cut_s.png`; the rest `<key>_cut.png`.)*

Art source library: `OneDrive\Desktop\SOCC\CHARACTERS` (and the `C` subfolder = the b43 refresh batch). More chars exist there to add if asked.
*(How to add a character — the sprite pipeline — is in PROJECT_BRIEF §7 + the memory note.)*

---

## Roadmap / next candidates (detail in PROJECT_BRIEF §11)
- **TURN server** — lets P2P connect through strict/mobile (CGNAT) NATs (currently STUN-only → those fall back to relay). Biggest remaining latency win.
- **4-player (2v2)** — requested, not built. Needs rooms-of-4 in `server.js` (+fly redeploy), 2v2 teams + 4-player render/collision, binary/delta snapshot encoding (~6× bandwidth), star-topology P2P. Multi-phase — defer, don't half-build.
- More characters available in `SOCC\CHARACTERS` on request.

## Watch-outs (live)
- OneDrive actively churns/dehydrates files in this folder (sprites, build.py have gone missing mid-session). Verify before building; `_cut` sprite backups are in the session scratchpad.

---

## Log
- b55: **Phase 2 — 6-stat model implemented** (per BASED_CUP_STAT_DESIGN.md; Phase 3 menu NOT built). Replaced old 3-stat STATS with 6 assignable stats (on-ball, off-ball, power, defense, dribble, stamina) for all 14, each totalling 36 (exact doc numbers); added `paceOf()` (=on+off, display). `statDerived` now yields `maxOn`/`maxOff`/`kickPow`/`stamDrain`/`stamRegen`/`defense`/`dribble`. Movement split into on-ball vs off-ball base speed, wired into `applyMove` (human), `applyMoveAI` (CPU, keeps its 0.92 handicap), and `predictGuestSelf` (guest prediction). Dribbling scales `glueBall` tightness (GRAB 0.30→0.55). **Steal is now a CONTEST** (replaced the auto-strip): when the defender's identical grabCap overlaps a dribbling carrier, `p=clamp(STEAL_BASE+ (defense−dribble)*STEAL_WEIGHT, 0.05,0.85)` resolves it, gated by `STEAL_TRY_GAP`/`STEAL_COOLDOWN` so it's not spammable — even match 0.30 (genuine contest, no auto-strip), big defender edge ~0.66–0.72, big dribbler edge clamps to 0.05. Small `DEF_CLOSE_BONUS` (0.06/def pt) to off-ball speed when chasing the carrier. **Sacred re-proven:** `grabCap` still constant 48; grep shows NO stat in any radius/cap; kick power still `kickPow*(0.55+0.45*charge)`, no velocity. Tunables listed under Current build. Behaviorally verified in-browser (totals=36, pace, on/off split human+CPU, glue + steal scaling). **STOP for user feel-test before Phase 3.** Sprint/stamina interaction resolved (see Current build note).
- b54: **AI difficulty overhaul — tiers now genuinely escalate.** Audit: `aiControl` easy/normal/hard shared 100% of logic and differed only in `spd`/`err`/`kick`; `setAim` aimed every tier at the goal-line at ball.y (≈center, no difficulty term) → normal beelined off kickoff and shot dead-straight, feeling like easy. Fix (AI-logic only, no stats/grabCap): per-tier `D` table now also carries `react` (move-target re-decide cadence: easy 13f / normal 5f / hard 1f → felt reaction gap), `aimErr` (shot scatter .40/.16/.05), `corner` (how much to aim at the goal corner AWAY from the human keeper .15/.62/.95), `lead` (ball anticipation) and `defend` (goal-side interception .15/.55/1.0). Added a per-possession random "plan" (`aiCorner`/`aiLane`, refreshed on possession change + rarely mid-possession) so approach varies turn-to-turn (no fixed beeline). Shots now aim at a goal corner away from the keeper. **Behaviorally verified in-browser** from the worst-case center dribble: mean shot cross-Y easy 317≈center / normal 370 / hard 404≈post; spread SD 52/30/6; shot freq 186/299/386; 0 throws across 1200 shot sims + 2160 mixed calls. The beeline-and-straight-shot tell on normal is gone; all three clearly distinct, easy stays forgiving. Kept independent of the upcoming stat redesign.
- audit (b53, no change): **character-equality audit — both equalities PROVEN, no drift, no fix.** (1) Hitbox: `grabCap(pl){return PLAYER_R+BALL_R+11;}` ignores `pl` → constant 48 for all; `PLAYER_R=24` is a single const; every collision/possession site uses constants; `STATS` only feeds speed/power/stamina via `statDerived` (never a radius). Identical for all 14. (2) Rendered size: `drawPlayer` draws an identical frame (w=R·FACE_FIT/FACE_RF, h=ih·s) because every `_cut` PNG is exactly 360×450; measured each PNG directly — **chin line `bot=377` for all 14** (perfect chin alignment) and cheek-dominant faces hit `FACE_W=200` exactly (pepe/trumpe/doomer/sadjak/wojak ≈200). In-game head-bbox varies (pepe smallest ~57px H, obampe largest ~83px H) purely from hair/ears/beard extending past the normalized cheek line — **by design** (`process_sprites.py` normalizes cheek-width + chin only; "hair/ears extend naturally"). No fairness/size defect; touched nothing (per "don't rebuild what's correct"). Ship gate re-run clean (0 tokens, 0 placeholders, harness OK); no code change so no badge bump / no deploy.
- b53: **fixed the live `toLowerCase` of undefined @1094 TypeError (real CODE bug).** Mapped built `index.html`:1094 → template:1094 (1:1, both 3571 lines): the global `keyup` handler `keys[e.key.toLowerCase()]=false; keys[e.code.toLowerCase()]=false;` (and keydown @1091/1092). Root cause: real `KeyboardEvent`s always carry `key`/`code`, but **synthetic key events from browser autofill + extensions (Phantom wallet, password managers) arrive as generic events with `key`/`code` undefined** → `.toLowerCase()` threw, firing 2× (keydown+keyup) and at arbitrary times incl. mid-match. REPRODUCED in-browser (`dispatchEvent(new Event('keyup'))` → exact `@line:1094` throw), then confirmed GONE after the fix (synthetic events now fire 0 errors; real KeyboardEvents still work). Fix: guard `if(typeof e.key!=='string') return;` on both handlers + guard `e.code` independently (missing values are legitimately possible, so defensive guard is correct). Separately pixel-proved `drawPlayer` renders all chars in-match (pepe/chad/soyjak/wojak each draw 2.8k–4.1k head pixels) — the "blank in-match" was the earlier b46 cache, not a render bug. Harness passed while this shipped (it doesn't dispatch synthetic key events) — that's why prior sprite-file/cache audits missed it.
- b52: **"sprites disappeared" bug report — root-caused as NOT a build defect.** Diagnosed the 3 known causes in order: (1) all 14 `_cut`/`_cut_s.png` present + non-zero on disk (no OneDrive churn), (2) deployed `index.html` had 0 leftover tokens AND 0 `TINY` placeholders, all 14 `*_SRC` constants filled with real base64 PNGs, (3) `THRESH3=110` (correct). Runtime check in a real browser: all 14 `IMG` objects load at 360×450, `blankOrFailed:[]`, title scene renders a sprite. Conclusion: the b51 artifact renders all sprites — the live symptom is environmental (stale cache / b51 deploy not propagated; live was b46 before the recent push). Action: bumped badge → b52, clean rebuild + full ship gate, pushed to force a fresh Vercel deploy so the live build is confirmable. ⚠️ If the live badge still shows b46/blank after hard-refresh, the issue is the Vercel project's production-branch wiring, not the code. No code/sprite change was needed.
- b51 (deploy): **git wiring + first git-push deploy.** Made the working folder a real git checkout on `main` tracking `origin/main`; merged the deployed repo assets (`api/`, `package.json`, `supabase-schema.sql`, `README.md`) with the full local source via an unrelated-histories merge (only overlap was `index.html` — kept the validated b51, origin's old b46 stays in history). Pushed → `origin/main` `141b444`; Vercel auto-deploys from `main`. Deploy is now `git push` (was: manual upload) — CLAUDE.md updated. NOTE: the ~25 MB binary push takes >2 min — push in the background, don't kill on a foreground timeout. Next: TURN server or 2v2 when the user picks.
- b51 (docs): **docs consolidation** — three live docs (CLAUDE = laws, STATE = state, PROJECT_BRIEF = deep reference); archived the stale b24 deep briefing to `archive/HANDOFF.b24-snapshot.md` (its still-current infra/gotchas migrated into PROJECT_BRIEF §12–13); CLAUDE trimmed to 1 page of laws/guards/commands; STATE got this pinned end-of-session rule + status board. No game code changed (badge bump only).
- b50: crash-proof guard on `EXTRA_CHARS` (un-built file can't dead-screen) + root-caused the "won't start" bug = user was deploying `game_template.html` not `index.html`.
- b49/b48: on-screen error reporter (+ copy button).
- b47: head-soccer drawPlayer (no ring, face-centred, team pool).
- b46: face-normalised sprites (chin-aligned, consistent size) + per-char ADJUST.
- b45: invisible-face fix (THRESH3 110), neck/crop rework, ball rubber-band fix, intro tap-to-skip.
- b44: intro reveal. b43: 13-char art refresh. b41/b42: mobile layout + overlay scroll.
- b40: 60/55Hz tick + lower interp floors. b39: 7 more chars + WebRTC P2P. b38: warmed server-ping. b37: mobile control/aim fixes.
