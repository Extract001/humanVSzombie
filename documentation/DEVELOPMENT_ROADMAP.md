# LAST SIGNAL — Development Roadmap

Statuses: NOT STARTED · IN PROGRESS · IMPLEMENTED · TESTED · VERIFIED · BLOCKED
*IMPLEMENTED = code exists. TESTED = automated checks pass (label says which kind). VERIFIED = you played it on Windows / in the browser and confirmed it.*

Test labels used in every report: `[LINUX-AUTO]` · `[WIN-AUTO]` · `[WIN-PLAY]` · `[WEB-EXPORT]` · `[VISUAL]` (see TECHNICAL_ARCHITECTURE §5).

## Phase 0 status (revised 2026-11-08, second review)

| Item | Status |
|------|--------|
| Documents created | **Completed** |
| Owner decisions recorded (shove, backpack death rule, Git, browser testing) | **Completed** (v0.2) |
| First owner review: general direction and architecture | **Approved**, with 5 corrections requested |
| Corrections (local darkness, SHOVING state, quest guarantees, Walker test plan, QA additions + WIN-AUTO) | **Completed** (v0.3), awaiting your check |
| Technical validation | Only the checks actually performed are listed below |
| Phase 1 approval | **Approved by owner (2026-11-08)** |

Checks actually performed in Phase 0:
1. Found `Godot_v4.7.2-stable_win64.exe` and `_console.exe` in `C:\Al-am\Game_engine\`. *The version comes from the file name, and your existing `virtual-world` project lists feature "4.7". I have **not** run the Windows executable.* Please confirm in Godot: **Help → About** should show `4.7.2.stable`.
2. Downloaded the official Godot 4.7.2 Linux build into my workspace; `--version` printed `4.7.2.stable.official.ed1daf0bf`. `[LINUX-AUTO]`
3. Confirmed `C:\Al-am\Game_development` was empty before writing, and that the 10 written files arrived with the expected sizes and checksums.
4. **Lighting proof of concept** `[LINUX-AUTO]`: a throwaway test project (kept outside your game project; screenshot and code in `documentation/research/`) rendered with Godot 4.7.2's Compatibility renderer on software OpenGL (Mesa llvmpipe) under a virtual display. 6/6 brightness checks passed: the street stays lit (0.459), the interior is dark (0.053), the flashlight lights the interior (0.395), the shelf blocks the flashlight (0.053), zombie eyes are readable in the dark (0.826). **Not** a Windows or browser test.
5. No game code exists yet, so no gameplay, Windows or browser tests have been run.

## Smallest playable MVP ("vertical slice")

The goal is the **shortest path to the full loop** on a small map. Everything else is layered on top.

> Start in safehouse → walk out → loot the grocery store → Walkers react to noise → fight with bat/pistol → return → deposit food → objective completes → save → quit → Continue works.

MVP content: safehouse + residential street + grocery store + pharmacy · Walker only · bat + pistol + shove · 8 items · 2 objectives · recoverable death backpack · HUD + inventory + pause + death screen + main menu · JSON save.
Then the **first release** adds: warehouse (dark, flashlight), vehicles + alarm car, knife + shotgun, Runner, bolt cutters gate, radio repair ending, final art/audio, web build.

## Phases

| # | Phase | Key deliverables | "Done" means | Status |
|---|-------|------------------|--------------|--------|
| 0 | Research & planning | GDD, architecture, roadmap, QA checklist, risks, asset strategy | You approve the plan | **COMPLETED** (approved 2026-11-08) |
| 1 | Playable prototype + **first web export** | project.godot + input map, player (move/run/stamina), camera, test yard map (TileMapLayer), 1 Walker that chases, HealthComponent, damage, game-over + restart, test runner, validate.bat, **export_presets.cfg + minimal Web build (test yard + movement) that loads and runs**. The test yard also has **one small dark room** using the approved local-darkness approach (no flashlight yet), so browser lighting cost is measured from day one | You press F5, move, get chased and killed, restart **and** the web build runs in your browser **and** walking into the dark room doesn't darken the yard | **TESTED** `[LINUX-AUTO]` + automated `[WEB-EXPORT]`; `[WIN-AUTO]` 37/37 passed on your PC; gameplay covered by your Phase 2 play-test. Your browser check not yet reported |
| 2 | Combat | WeaponData + WeaponHolder, bat (melee arc), pistol (hitscan), magazine/reserve/reload, **quick shove**, zombie hurt/stun/death, hit flash, tracers, screen shake, basic HUD ammo | You kill zombies with both weapons, shove works as specified, ammo math always correct | **VERIFIED** (2026-11-08): `[LINUX-AUTO]` 66/66, `[WIN-AUTO]` 66/66 on your PC, `[WIN-PLAY]` passed (your report), automated `[WEB-EXPORT]` passed |
| 3 | Zombie intelligence + **noise core** | Full state machine, sight cone + raycast, think tick, NavigationAgent2D, wander/investigate/search, group alert, **NoiseSystem with gunshot noise** | Shooting in one street pulls zombies from the next; they lose you if you break line of sight | **TESTED, NOT VERIFIED**: behaviour passed in all categories (`[LINUX-AUTO]` 78/78, `[WIN-AUTO]` 78/78, `[WIN-PLAY]` all working, arenas balanced, browser working). **Performance failed: 30 FPS on your laptop vs. the 60 FPS target**; under investigation (QA_CHECKLIST Phase 3) |
| 4 | Exploration & environment | Ashford Lane map (MVP areas), doors, interactables, nav mesh, collisions, area transitions | You walk the whole neighbourhood; no wall clipping | **TESTED** `[LINUX-AUTO]` 88/88, `[WIN-AUTO]` 88/88 on your PC; automated `[WEB-EXPORT]` (doors and gate opened with E in headless Chrome, 0 errors). Awaiting `[WIN-PLAY]`, `[VISUAL]` |
| 5 | Loot & inventory | ItemData, LootTable, LootContainer (persistent IDs, **guaranteed_items**), search timer, inventory (12 slots), stacking, full-inventory handling, use/drop, **death backpack (in-session)**, **quest-guarantee tests** | Loot every container; reopen; no duplication (tests prove it) | **TESTED** `[LINUX-AUTO]` 110/110 (117 with Phase 6); automated `[WEB-EXPORT]` (inventory, drop, pile pick-up in headless Chrome, 0 errors). Awaiting `[WIN-AUTO]`, `[WIN-PLAY]`, `[VISUAL]` |
| 6 | Noise & light (full) | Run/loot/smash noise, HUD noise meter, world rings, dark zones, flashlight + batteries, light-affects-sight, **browser performance + compatibility test of lighting (Chrome, Edge, Firefox)** | You can sneak past zombies by walking and keeping the light off | **TESTED** `[LINUX-AUTO]` 117/117 + 2 render tests; automated `[WEB-EXPORT]` (0 errors); `[WIN-AUTO]` 117/117 on your PC (render tests not yet run there). Awaiting `[WIN-PLAY]`, `[VISUAL]`, browser FPS in Chrome/Edge/Firefox |
| 7 | Safehouse & progression | Stash, bed (heal + save point), objective board, ObjectiveTracker, bolt cutters gate, radio repair chain | Clear reason to leave and come back; chain completes | **TESTED** `[LINUX-AUTO]` 128/128 (full chain on guaranteed items, 3 seeds); automated `[WEB-EXPORT]` (0 errors). Awaiting `[WIN-AUTO]`, `[WIN-PLAY]`, `[VISUAL]`. Saving at the bed → Phase 10 |
| 8 | UI & game flow | Main menu, pause, settings (audio, fullscreen, rebinding), inventory/stash screens, death screen with stats, styled theme | Every button works; no default-Godot look | **TESTED** `[LINUX-AUTO]` 135/135; automated `[WEB-EXPORT]` (0 errors). Awaiting `[WIN-AUTO]`, `[WIN-PLAY]`, `[VISUAL]`. Continue (load) → Phase 10 |
| 9 | Art, animation, audio | Final tileset, player/zombie animations, weapon FX, lighting polish, SFX, ambience, music, credits | Consistent look and sound; every asset passes the Phase 9 checks in the QA checklist (art, animation, audio, licences) | **TESTED** `[LINUX-AUTO]` 144/144; automated `[WEB-EXPORT]` (0 errors). All assets original (owner decision). Awaiting `[VISUAL]`, `[WIN-PLAY]`, browser audio check |
| 10 | Save system (full) | Save/continue for everything (incl. backpacks, autosave on death), versioning, corruption fallback | Close and reopen without losing valid progress | **TESTED** `[LINUX-AUTO]` 151/151; automated `[WEB-EXPORT]` (save survives a page reload, 0 errors). Awaiting `[WIN-AUTO]`, `[WIN-PLAY]` |
| 11 | Optimisation & QA | Profiling (40 zombies), memory, full QA checklist, browser + Windows passes | All critical/major bugs fixed | NOT STARTED |
| 12 | Export & publishing | Windows .exe, web build, icon, cover, screenshots, trailer clip, itch.io page text | Build uploaded as an itch.io draft for your review | NOT STARTED |

### Changes from your original roadmap (and why)
1. **Basic noise moves into Phase 3.** Zombie "investigate" behaviour needs something to investigate. Gunshot noise lands with the AI; Phase 6 adds the rest (footsteps, smashing, light).
2. **Browser export is tested from Phase 1** (owner request), then again in Phase 6 when lighting arrives, and in every phase after that, not just Phase 12.
3. **Save-friendly design starts in Phase 5** (persistent container IDs, all state in `GameState`), so Phase 10 is wiring, not a rewrite.

## Walker difficulty testing (owner decision: keep values, test before changing)

Initial Walker values stay (chase 45 px/s vs. player walk 80 px/s). Difficulty is judged from **measured gameplay**, not guesses.

**Automated simulation scenarios** `[LINUX-AUTO]` (Phase 3, re-run whenever AI or values change). Each runs headless with physics stepping and records *damage taken, bites landed, time to escape or death*:

| # | Scenario | What it measures |
|---|----------|------------------|
| S1 | 1 Walker, open yard, player walks away | Baseline: player should escape, 0 bites |
| S2 | 3 Walkers approaching from different sides, open yard | Whether walking still escapes groups, or forces running/shoving |
| S3 | 1-tile-wide corridor, 2 Walkers ahead and 1 behind | Confined space: does shove + melee get the player through? |
| S4 | Small store room, one door, player searching a 1.2 s cabinet while 2 Walkers enter | Looting pressure: damage taken while searching |
| S5 | 5 Walkers in a dark room, player with no light | Darkness + numbers |
| S6 | Pistol shot in the street, 6 Walkers in the 480 px noise radius | How fast a crowd forms after noise |

Scripted "player bots" use simple fixed behaviour (walk away / shove when adjacent / search then flee) so results are repeatable and comparable after tuning.

**Manual arenas** `[WIN-PLAY]`: the same six setups exist as playable test scenes (`scenes/tests/arena_*.tscn`, debug builds only), so you can feel each one. After each, I'll ask: *too easy / about right / too hard?*

**Decision rule:** values change only if the automated metrics **and** your play-test agree. Every change is logged in the GDD decision log with before/after numbers.

### Phase 3 measurements (2026-11-08, `[LINUX-AUTO]`, Walker values unchanged)

| Scenario | Bot behaviour | Result (3 runs each) |
|----------|---------------|----------------------|
| S1 open yard, 1 Walker | walks away | Escaped every time, 0 damage, ~250 px gap after 5 s |
| S2 open yard, 3 Walkers | walks away from the group | Survived every time, 0 damage, never needed to fight |
| S3 1-tile corridor, 2 ahead + 1 behind | pushes through with shove + bat | Escaped every time, 0 damage, 2 kills, 5 shoves, 9.2 s |
| S4 store room, searching 1.2 s | searches, then fights out | Escaped, 0 damage, 0 bites while searching (Walkers arrived after the search ended) |
| S5 dark room, 5 Walkers, no light | fights across the room | Escaped, **48–60 damage** (4–5 bites), 4 kills |
| S6 pistol shot, 6 Walkers | fires once, then holds position | 4 of 6 heard it (exactly the 4 in range; the one behind the wall and the far one didn't), first arrived after 2.3 s |
| 40 Walkers chasing (performance) | — | 0.4–0.5 ms per frame on average, worst 2.1–2.3 ms (headless, 2-core server CPU, no rendering) |

**What the data says (no values changed):**
- A single Walker, or a small group in the open, is no threat to a player who keeps walking. That matches the design, but the bots react instantly and perfectly, so a real player will do worse.
- The bot takes real damage only when Walkers are numerous **and** close (S5).
- A 1.2 s search isn't threatening on its own: in S4 the Walkers needed about 3 s to arrive. Phase 5 searching noise and more Walkers near loot will add pressure.
- The pistol's 480 px noise works as designed: shooting reliably pulls in everything within range within a few seconds.

**Next step:** your play-test of the arenas (F1–F6) decides. Options *if* you also find it too easy, to be confirmed by you first:
- 1–2 more Walkers near loot spots.
- Walker chase speed 45 → 55.
- Search times 1.5–2 s.

## Asset strategy

| Stage | Visuals | Audio |
|-------|---------|-------|
| Phases 1–8 (prototype) | **Original placeholder sprites I generate with code** (simple but readable pixel shapes: survivor, walker, tiles, icons). Clearly labelled PLACEHOLDER. | Original procedurally generated SFX (sfxr-style) or silence |
| Phase 9 (production) | Option A, recommended: a free **CC0** base, such as [Kenney.nl](https://kenney.nl) packs (public domain, commercial OK, no attribution required). Note: Kenney's top-down art is clean and cartoony, not gritty, so it would need recolouring to the muted palette. <br>Option B: a free or paid itch.io top-down zombie pixel pack. **Each licence verified and recorded before use; anything paid needs your approval.** <br>Option C: commission an artist for the player and zombies (best identity, costs money). | CC0 SFX (Kenney audio, Freesound items marked CC0 only), music from CC0/CC-BY sources with attribution recorded |
| Fonts | Google Fonts / OFL pixel fonts (free, commercial OK) | — |

**Honest limitation:** I can make clean, consistent *simple* pixel art with code, good enough for a readable prototype and possibly a stylised minimal look. I can't produce hand-animated, detailed gritty pixel art at commercial quality. Phase 9 needs a decision between options A, B and C. I'll present real candidates with their licences when we get there.

## Git workflow (owner decision)
- Local repository first, created by **you** (commands in README → "Git setup"). GitHub remote `https://github.com/Extract001/humanVSzombie.git` is connected later.
- Before each substantial change I tell you exactly which commit command to run, or I ask you to confirm that you've committed.
- I never run `git reset`, `git clean`, `git checkout -- <file>`, force-push, or delete or overwrite existing files without your explicit approval.

## Workflow per phase
1. Git commit checkpoint (you run it; I give the command).
2. Build the smallest working piece, then run automated checks (parse, import, scene load, tests) with Godot 4.7.2 headless.
3. Fix, then expand.
4. Phase report: implemented / files / tests run + results / known problems / **your manual test steps** / next.
5. You play-test, then the status becomes VERIFIED.
