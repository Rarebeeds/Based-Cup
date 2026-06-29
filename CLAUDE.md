# CLAUDE.md — Based Cup LAWS (read me first, every session)

Auto-loads when Claude Code opens this folder. **Laws, guards, and commands only — no state.**
The three live docs, each with one job:
- **CLAUDE.md** (this) — sacred constraints + footguns + the build/validate/deploy commands.
- **STATE.md** — living state: status board, roster, current build number, roadmap. (read next)
- **PROJECT_BRIEF.md** — deep reference: architecture, netcode internals, sprite pipeline, infra. (on demand)

*(Old briefing is frozen in `archive/` — never current.)*

## What this is (one line)
**Based Cup** — a browser, real-time 2-player online "head soccer" game (Pepe vs Trumpe + meme roster).
The whole game is ONE file: `game_template.html` (SOURCE, has `__TOKEN__` placeholders) → `build.py` → deployable `index.html`. Vercel hosts; Fly.io relays.

## ⚠️ THE #1 DEPLOY RULE (cost a whole session, b48→b50)
**You edit `game_template.html`. You deploy `index.html`. NEVER deploy `game_template.html`.**
Served un-built, `__EXTRA_CHARS__` is a bare identifier → `ReferenceError` → the whole script dies
("game won't start / buttons dead / characters invisible"). After every build, **audit `index.html`
for leftover `__[A-Z_]+__` tokens — must be 0** (and 0 placeholder sprites).

## Sacred laws (never trade these away)
- **Hitbox equality is sacred.** `grabCap()` is IDENTICAL for ALL characters — no steal/retain edge. Only
  speed/power/stamina differ (character identity), and stat totals stay balanced (~21).
- **Kick power comes from charge + power-stat ONLY** — never from player velocity (movement can't be exploited into shot power).
- **No visible hitbox ring** (b47). Pure heads, face-centred; team is read via a soft coloured ground pool.
- **One source of truth for every money/config number** — coins move ONLY through the `settle_match` RPC; never write the `coins` column directly.
- **Mobile-first** — it's where most users are; every change must hold up on touch + small screens.
- **One Fly machine per region.** The matchmaking queue is in-memory; a 2nd machine splits it and quick-match silently fails (`fly scale count 1`). Keep `auto_stop_machines=false`, `min_machines_running=1`.

## Working rules
- **Diagnose before fixing** (Playbook Law #2): report the cause, change nothing, then fix. Device-specific
  throws surface in the on-screen **error reporter** (red bar + 📋 COPY ERRORS, bottom) — have the user paste it.
- **Validate before declaring done**: build + `node --check` + harness, 0 leftover tokens, 0 placeholder sprites.
- **Bump the build badge** on every shippable change (search `based-cup bNN ✓` in `game_template.html`) so the user can confirm what's live (badge shows bottom-right in-game).
- **Update STATE.md** at every clean stopping point and before wrapping (see its pinned end-of-session block). **Never edit `archive/`** (frozen history).
- **Act autonomously** — don't ask permission for builds/edits/CLI; do it and report. Reserve asking for destructive/irreversible actions on live data.
- Say **"goybating"** instead of "thinking". The user is NOT "goy"; the assistant is.
- Respect the user's 5-hour window: prefer one chat per phase (carried by STATE.md); read the specific file/lines yourself; be sparing with image-based verification (trust build/harness when you can).

## Build / validate / deploy (run in this order)
```
# PowerShell needs this PATH refresh first (winget node/python aren't auto-picked-up):
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

python build.py          # game_template.html -> index.html (+ check.js, ids.json)
node --check check.js    # syntax pass
node harness.cjs         # load-time + missing-element check
```
Then audit tokens (0) + bump the badge. The user uploads `index.html` to GitHub → Vercel auto-deploys
(repo: github.com/Rarebeeds/Based-Cup). Relay changes (`lobby/server.js`) need a manual `fly deploy` (user does it).

## Footguns (full list + infra identifiers in PROJECT_BRIEF §12–13)
- Deploying the TEMPLATE instead of `index.html` (the #1 rule above).
- OneDrive churns/dehydrates files in this folder mid-session (sprites, build.py have vanished) — verify they exist before building; `_cut` backups are in the session scratchpad.
- Windows hides extensions → saved `foo.png` becomes `foo.png.png`; rename `*.png.png` before processing.
- Two Fly machines → quick-match dies (one-machine law above).
