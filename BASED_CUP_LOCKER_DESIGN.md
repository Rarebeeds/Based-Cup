# BASED CUP — CHARACTER MENU / LOCKER (design spec)
*Approve/adjust before the build. This is the foundation for the Fortnite-style pre-queue flow and 2v2. FIFA-clean look, Fortnite locker structure.*

---

## What it is
A main-menu **locker** where the player browses all 14 characters, sees each one's stats/archetype, and **equips** one as their active character. The equipped character is what they queue into matches with — there is **no per-match character-select screen anymore** (Fortnite-pure: equip in the locker, then queue straight in).

## The core change it introduces: "equipped character"
- A persistent **equipped character** per player (stored locally + mirrored to Supabase profile, same pattern as other profile data).
- **Quick Match, Wager, Practice, Play-a-Friend all read the equipped character** instead of showing a pick screen. The old in-flow character select is removed/bypassed.
- Default on first run: pepe (or current default) so a brand-new player always has something equipped.
- This is the hook 2v2 needs: you equip before you queue, so a party member's character is already known when matchmaking fires.

---

## Look & feel — FIFA-clean
- Sleek, sharp, **slightly light** (not a dark theme) — premium, bright, clean soccer aesthetic.
- This screen is also the **first screen reskinned in the FIFA-clean UI remodel** — so its design tokens (font, palette, card style, spacing, button style) become the reference the rest of the UI later matches. Build the look here deliberately; it sets the system.
- Card-forward layout: each character shown as a clean stat *card* (think FIFA Ultimate Team card energy, but your meme-head art) — head art, name, archetype label, the 6 stats + derived Pace.

---

## Layout (Fortnite locker structure)
1. **Grid/carousel of all 14 characters** — browse, tap to select-and-preview.
2. **Detail panel** for the selected character: large head art, name, **archetype** (Wall / Dribbler / Speedster / Powerhouse / All-rounder), the **6 stats** (on-ball, off-ball, power, defense, dribbling, stamina) shown as clean bars/numbers, and **Pace** as the headline derived figure.
3. **EQUIP button** — sets this as the active character. Clear "EQUIPPED" state on the currently-active one (Fortnite shows a checkmark/highlight on equipped).
4. Entry point: a clear **Locker / Characters** button in the main menu.

## Stats display (uses the locked stat model)
- Show all 6 assignable stats + **Pace** (= on-ball + off-ball, derived) as the big number.
- Read the numbers from the existing STATS data — single source of truth, do NOT hardcode a second copy. If the stat model changes, the locker reflects it automatically.
- Show the **archetype** label per character (from the stat-design doc's grouping).

---

## Collection-ready (critical — build for the future without building it now)
The locker must be structured so the **collection / packs / ownership** layer slots in later WITHOUT a rewrite:
- Model each character as having an **owned** state, even though **right now everyone owns all 14** (owned = true for all). The grid reads an "owned" flag per character; today it's always true.
- Leave a clean seam for **rarity** (cosmetic only — common/gold/holo of the same card; never changes stats, per the sacred fairness rule) so cosmetic variants can be added later.
- This means when packs ship, "unlock" just flips owned=false→true and the locker already handles locked/owned display — no restructure.
- Do NOT build packs, ownership logic, or rarity now. Just don't architect them out.

---

## Hard rules / constraints
- **Equipped character replaces per-match pick everywhere** (quick/wager/practice/friend) — verify no flow still shows the old select screen, and no flow breaks from its removal.
- **Single source of truth for stats** — locker reads existing STATS; no duplicate stat data.
- **Fairness intact** — the locker shows stats but changes no gameplay; grabCap stays constant; equipping a character never alters hitbox. It's display + selection only.
- **Mobile-first** — most players are on phones; the grid + detail + equip must work cleanly on a phone (the locker is a menu, so it follows the existing overlay-scroll / safe-area patterns).
- **Don't regress** — accounts, the equipped value persisting across sessions (local + Supabase), and all existing menu flows keep working.

---

## Build phasing (don't mega-build)
- **Phase 1 — the locker + equip + wire it into the flows.** Grid of 14, detail panel with stats/pace/archetype, EQUIP, equipped-character read by quick/wager/practice/friend, persisted local+Supabase, FIFA-clean look. Ship + feel-test.
- **Phase 2 (later) — collection/packs** slot into the owned-flag seam. NOT now.

One build prompt for Phase 1, written after this spec is approved.

---

## Open calls for you
1. **Grid vs carousel** for the 14 — a full grid (see all at once, FIFA-roster feel) or a swipe carousel (one big card at a time, Fortnite-locker feel)? *Recommend: grid on desktop, sw8ipe-friendly on mobile — but pick the primary feel.*
2. **Where the Locker button lives** in the main menu — top-level button, or inside a profile/character area? *Recommend: top-level, it's central now.*
3. Anything you want on the card beyond art + name + archetype + 6 stats + pace (e.g. a flavor line, win record with that character)? *Recommend: keep it clean for now, add later.*
