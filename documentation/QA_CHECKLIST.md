# LAST SIGNAL — QA Checklist

Version 0.3 (revised 2026-11-08 after second owner review)

Each check is labelled with **who/where** it is tested. A pass in one category never counts as a pass in another.

| Label | Meaning |
|-------|---------|
| `[LINUX-AUTO]` | Automated, run by Claude on Godot 4.7.2 **Linux** (headless, or software-OpenGL render tests). Proves code/data correctness and relative behaviour only. |
| `[WIN-AUTO]` | Automated, run on **your Windows** Godot 4.7.2 via `tools/validate.bat` (import, scene load, test suite). Result in `logs/validate.log`. |
| `[WIN-PLAY]` | **Played by you on Windows** (editor F5 or exported .exe), following given steps. |
| `[WEB-EXPORT]` | **HTML5 build** exported and run in a browser (Claude's headless load test and/or you in Chrome/Edge/Firefox). |
| `[VISUAL]` | **Manual visual / feel / audio check** by you. |

Mark each: ✅ pass · ❌ fail (write the bug) · ⏳ not yet testable. A feature is **VERIFIED** only when its `[WIN-PLAY]` and `[VISUAL]` items pass (plus `[WEB-EXPORT]` where listed).

## Every phase (regression gate)
- [ ] `[LINUX-AUTO]` Project imports with zero `ERROR` / `SCRIPT ERROR` / `Parse Error` lines
- [ ] `[LINUX-AUTO]` Every `.tscn` loads and instantiates without missing resources
- [ ] `[LINUX-AUTO]` `tests/run_tests.gd` passes 100%
- [ ] `[WIN-AUTO]` `tools/validate.bat` prints `VALIDATION PASSED` on your Windows Godot 4.7.2
- [ ] `[WIN-PLAY]` F5 launches the game; Output panel shows no red errors during 2 minutes of play
- [ ] `[WEB-EXPORT]` Web build exports without errors and reaches the game scene

## Phase 1 — Prototype
**Movement & stamina**
- [ ] `[LINUX-AUTO]` Diagonal input vector length ≤ 1.0; walk/run speeds match data (80 / 140 px/s)
- [ ] `[LINUX-AUTO]` Stamina drains 20/s while running; never below 0 or above 100
- [ ] `[LINUX-AUTO]` **Minimum stamina to run:** with stamina < 10, holding Shift does *not* start a run (speed stays 80); at ≥ 10 it does
- [ ] `[LINUX-AUTO]` Running continues until stamina hits 0, then drops to walk; can't restart until stamina ≥ 10
- [ ] `[LINUX-AUTO]` Regeneration: none during the 1 s delay after running stops, then 15/s
- [ ] `[WIN-PLAY]` WASD moves smoothly; Shift runs; running stops when the stamina bar is empty

**Health & death**
- [ ] `[LINUX-AUTO]` Damage reduces health; health clamps to 0..max; `died` fires exactly once
- [ ] `[LINUX-AUTO]` Simulation: Walker placed 100 px away with clear line of sight reaches the player and deals 12 damage per bite at ≥ 1.2 s intervals
- [ ] `[WIN-PLAY]` Walker chases; bites hurt; death shows the game-over screen; Retry restarts cleanly

**World**
- [ ] `[WIN-PLAY]` Can't walk through walls or crates; no snagging on wall corners
- [ ] `[VISUAL]` Camera follows smoothly; no pixel jitter or blur; placeholder sprites readable

**Local darkness test room**
- [ ] `[LINUX-AUTO]` Render test: yard brightness unchanged with the player inside vs. outside the dark room, and with darkness on vs. off; room floor < 15% of **the same floor's** brightness without darkness *(corrected 2026-11-08: comparing against the yard's grass was unfair because the floors are different materials)*
- [ ] `[WIN-PLAY]` Walking into the dark room does **not** darken the yard; walking out doesn't flash or pop
- [ ] `[VISUAL]` Doorway edge looks like a soft gradient, not a hard box; the room's roof/outer walls aren't blackened when seen from outside

**Web build**
- [ ] `[WEB-EXPORT]` Minimal web build (test yard + movement + dark room) loads in Chrome and Edge on Windows; WASD works after clicking the game; no errors in the browser console (F12)
- [ ] `[WEB-EXPORT]` FPS counter ≥ 55 in the yard and in the dark room

## Phase 2 — Combat
**Player states (no invincibility)**
- [ ] `[LINUX-AUTO]` Damage is applied in NORMAL, ATTACKING, RELOADING, **SHOVING** and HURT; ignored only in DEAD
- [ ] `[LINUX-AUTO]` Every transition in the state table (TECHNICAL_ARCHITECTURE §4.3) behaves as specified; illegal transitions are refused (e.g. shove during ATTACKING)
- [ ] `[LINUX-AUTO]` Walker bites never put the player in HURT (no stun-lock); a ≥ 25 damage hit does, for 0.3 s

**Shove**
- [ ] `[LINUX-AUTO]` Costs 15 stamina; refused below 15; 1.0 s cooldown enforced
- [ ] `[LINUX-AUTO]` Pushes every zombie inside the 120° / 36 px cone and none outside it; staggered zombies can't bite for 0.6 s
- [ ] `[LINUX-AUTO]` **Stamina regeneration after shoving:** no regeneration for 1 s after the shove, then 15/s
- [ ] `[LINUX-AUTO]` Shove during RELOADING cancels the reload with no ammo change
- [ ] `[VISUAL]` Shove has a visible animation, a whoosh, and a thud on contact

**Weapons & ammo**
- [ ] `[LINUX-AUTO]` Firing decreases the magazine by exactly 1 (shotgun: 1 shell, N pellets)
- [ ] `[LINUX-AUTO]` Can't fire with an empty magazine; reload with 0 reserve does nothing
- [ ] `[LINUX-AUTO]` Reload is atomic: magazine + reserve before = after a completed reload; cancelling moves nothing
- [ ] `[LINUX-AUTO]` **Weapon switching without duplication:** 1,000 random sequences of fire / reload / cancel / switch keep *(all magazines + reserve + rounds fired)* constant; each weapon keeps its own magazine count after switching away and back
- [ ] `[LINUX-AUTO]` Zombie at 0 HP enters DEAD exactly once (one kill counted)
- [ ] `[WIN-PLAY]` Fire rate and melee cooldown can't be exceeded by spamming
- [ ] `[WIN-PLAY]` Switching weapons mid-reload cancels the reload cleanly; the HUD ammo numbers stay correct
- [ ] `[VISUAL]` Hits readable (flash, knockback, sound); misses show a tracer to the wall
- [ ] `[LINUX-AUTO]` Every combat action requests its sound (swing, shove, shot, hit, death, dry fire)
- [ ] `[LINUX-AUTO]` A killed zombie stays visible as a corpse, no longer blocks movement and can't be hit again
- [ ] `[VISUAL]` (audio) Gunshot clearly louder than melee; the zombie grunt when it spots you is a useful warning

## Phase 3 — Zombie AI & Walker difficulty
*Results recorded 2026-11-08. Sources: Claude's Linux runs; your `logs\validate.log` (02:02, read by Claude); your written test report (02:22).*

- [x] ✅ `[LINUX-AUTO]` Zombie behind a wall does **not** see the player
- [x] ✅ `[LINUX-AUTO]` Zombie inside the noise radius enters INVESTIGATE; outside it doesn't
- [x] ✅ `[LINUX-AUTO]` Difficulty scenarios S1–S6 run and their metrics are reported (3 seeds each; table in DEVELOPMENT_ROADMAP)
- [x] ✅ `[LINUX-AUTO]` A wall between a noise and a zombie halves the noise radius
- [x] ✅ `[LINUX-AUTO]` Investigating zombies path around walls to the noise; chasing zombies follow the player around corners
- [x] ✅ `[LINUX-AUTO]` Searching zombies look around, then give up after 6 s; idle zombies wander and stay near their area
- [x] ✅ `[LINUX-AUTO]` Spotting the player alerts zombies within 140 px; hearing a groan never causes another groan
- [x] ✅ `[LINUX-AUTO]` A pistol shot reaches zombies within 480 px in the open, not behind walls beyond 240 px
- [x] ✅ `[LINUX-AUTO]` Calm zombies over 700 px away go dormant and wake up on noise
- [x] ✅ `[WIN-AUTO]` `validate.bat`: **ALL TESTS PASSED (78)** on your Windows Godot 4.7.2 (log 2026-11-08 02:02)
- [ ] ⏳ `[WIN-AUTO]` `validate.bat scenarios`: not run yet (no scenario table in your log). Optional, as your arena play-test covers difficulty
- [x] ✅ `[WIN-PLAY]` Walkers wander on their own (your report: WORKING)
- [x] ✅ `[WIN-PLAY]` In the test yard, fire the pistol: Walkers come to the shot (your report: WORKING)
- [x] ✅ `[WIN-PLAY]` Zombies path around obstacles (your report: wall navigation WORKING)
- [x] ✅ `[WIN-PLAY]` Spotting the player brings nearby Walkers (your report: group alerts WORKING)
- [x] ✅ `[WIN-PLAY]` After losing sight, the zombie searches, then gives up (your report: WORKING)
- [x] ✅ `[WIN-PLAY]` Play arenas S1–S6 (your report: BALANCED → no difficulty values change)
- [x] ✅ `[WEB-EXPORT]` Browser build plays (your report: WORKING) + Claude's headless-Chrome test, 0 errors
- [ ] ⏳ `[VISUAL]` Attack wind-up is visible; the player can step out of it: not reported separately
- [ ] ❌ `[WIN-PLAY]` **40 zombies: ≥ 60 FPS on your laptop.** Your result: **30 FPS**. Not met. Under investigation; the exact test conditions (editor or standalone, number of Walkers, V-Sync, power mode) weren't recorded
  - Investigation step 1 (Claude, 2026-11-08): no artificial cap in the project (`max_fps = 0`, physics 60/s, no low-processor mode). V-Sync is ON (default): on a 60 Hz screen, frames slightly over 16.7 ms drop the rate straight to 30.
  - Investigation step 2 (Claude, `[LINUX-AUTO]`, software GPU): 40 Walkers cost ~1.2 ms of physics + AI per frame. The largest drawing cost is 2D lighting (dark room, 40 Walkers: 6.1 ms GPU with lights, 4.0 ms without). Even this slow software renderer reached 86–94 FPS with 40 Walkers.
  - Investigation step 3 (**you**): `validate.bat perf` measures FPS, CPU and GPU time on your laptop (1/10/20/40 Walkers, yard and dark room, V-Sync on and off) and saves `logs\perf_benchmark.txt`.
- [ ] ⏳ `[WIN-PLAY]` `validate.bat perf`: 40 Walkers ≥ 60 FPS with V-Sync on, standalone run

**Phase 3 status: NOT VERIFIED.** All behaviour checks passed (automated and manual), but the 40-Walker performance requirement failed on your laptop (30 FPS) and its cause isn't identified yet.

## Phases 4–5 — World, loot, inventory, quests, backpack
**Loot**
- [x] ✅ `[LINUX-AUTO]` All `container_id`s unique
- [x] ✅ `[LINUX-AUTO]` Opening, closing and reopening a container never adds items (no duplication)
- [x] ✅ `[LINUX-AUTO]` Full inventory: items that don't fit stay in the container
- [x] ✅ `[LINUX-AUTO]` Stacking respects max stack; quantities never negative
- [x] ✅ `[LINUX-AUTO]` Searching is cancelled by moving or taking damage (also attacking and shoving); no items granted when cancelled

**Guaranteed quest-item availability**
- [x] ✅ `[LINUX-AUTO]` Each designated container in `quest_guarantees.tres` exists exactly once in the map
- [x] ✅ `[LINUX-AUTO]` Across 1,000 random seeds, every guaranteed item is present in its container (0 missing)
- [x] ✅ `[LINUX-AUTO]` Guaranteed food ≥ 7, water ≥ 5, medical ≥ 4 (each ≥ objective requirement)
- [x] ✅ `[LINUX-AUTO]` Navigation path exists from the safehouse door to the bolt-cutter container **with the warehouse gate closed** *(Phase 4 test: 96 tiles)*
- [x] ✅ `[LINUX-AUTO]` Navigation path exists to the radio-component container once the gate is opened *(Phase 4 test)*
- [x] ✅ `[LINUX-AUTO]` Quest items can't be dropped or used up *(selling doesn't exist in the MVP)*
- [ ] ⏳ `[LINUX-AUTO]` A save missing a required quest item (objective incomplete) gets it respawned in its designated container on load *(needs saving + objectives: Phases 7 and 10)*

**Death backpack**
- [x] ✅ `[LINUX-AUTO]` Death: all non-equipped carried items move to a backpack; equipped weapons and loaded rounds stay; item totals conserved *(stash arrives in Phase 7; re-check then)*
- [x] ✅ `[LINUX-AUTO]` **Backpack recovery with quest items:** die carrying bolt cutters / radio component → the backpack contains them → recovering returns them *("objective can still complete" re-checked when objectives exist, Phase 7)*
- [x] ✅ `[LINUX-AUTO]` Dying twice before recovery creates two backpacks; both keep their contents
- [x] ✅ `[LINUX-AUTO]` Backpack position is on walkable navigation (never inside a wall)
- [x] ✅ `[LINUX-AUTO]` **Respawn at 75 HP** at the safehouse bed point, in NORMAL state, with stamina full
- [ ] `[WIN-PLAY]` Die, respawn at 75 HP (check the health bar), walk back, recover the backpack; the HUD arrow points to it

**Phase 5 automated results (2026-11-08)**: `[LINUX-AUTO]` 110/110 (`validate.sh --render --scenarios` passed; scenarios unchanged from Phase 3). `[WEB-EXPORT]` headless Chrome: Tab opens the inventory, a bandage stack dropped with the Drop button, Tab closes, E on the pile opens it, E takes all back, then out through the door; 0 errors. *Not proof of Windows or real-browser behaviour.*
- [ ] ⏳ `[WIN-AUTO]` `validate.bat` → ALL TESTS PASSED (110)
- [ ] ⏳ `[WIN-PLAY]` Search a grocery shelf: bar fills under the player; moving cancels it ("Search interrupted"); finishing opens the loot panel; Take / Take all / Close work
- [ ] ⏳ `[WIN-PLAY]` Reopen the same shelf: same items, nothing new; an emptied shelf shows "(empty)" and looks darker
- [ ] ⏳ `[WIN-PLAY]` Fill the bag (e.g. take lots of scrap): "Bag full", the rest stays in the container
- [ ] ⏳ `[WIN-PLAY]` Tab / I: inventory shows slots and descriptions; use a bandage after being bitten (health rises over 3 s); drop something and pick it back up
- [ ] ⏳ `[WIN-PLAY]` Pickup truck bed (main street): bolt cutters are there; trying to drop them is refused
- [ ] ⏳ `[VISUAL]` Panels readable at your window size; item icons distinguishable; mouse cursor appears with a panel and the crosshair returns after

**World (Phase 4)** *(automated results 2026-11-08)*
- [x] ✅ `[LINUX-AUTO]` Map is 160 × 86 tiles; spawn inside the safehouse, not in a wall
- [x] ✅ `[LINUX-AUTO]` All 30 container ids unique; all 11 designated quest containers present exactly once
- [x] ✅ `[LINUX-AUTO]` No Walker starts inside a wall or vehicle (23 Walkers)
- [x] ✅ `[LINUX-AUTO]` Routes exist: safehouse→grocery (24 tiles), safehouse→pharmacy (68), back alley (48), bolt-cutter truck reachable with the gate locked (96)
- [x] ✅ `[LINUX-AUTO]` Locked warehouse gate blocks all paths; `unlock()` opens them after a rebake
- [x] ✅ `[LINUX-AUTO]` Closed door blocks the player; opening lets them through and makes a 40 px noise
- [x] ✅ `[LINUX-AUTO]` A door won't close on someone standing in the doorway
- [x] ✅ `[LINUX-AUTO]` A Walker pushing on a closed door bangs on it and can't get through
- [x] ✅ `[LINUX-AUTO]` Prompt appears only in reach **and** facing; E uses it; prompt text updates (Open/Close)
- [x] ✅ `[LINUX-AUTO]` Roof fades when entering, returns when leaving; location name shown
- [x] ✅ `[LINUX-AUTO]` Map has ≤ 8 dynamic lights, none casting shadows (performance guard)
- [x] ✅ `[WEB-EXPORT]` Headless Chrome: walk to the safehouse door, E, walk out, E on the yard gate, reach the street; 0 errors
- [x] ✅ `[WIN-AUTO]` `validate.bat` → ALL TESTS PASSED (88) *(your log `logs/validate.log`, 02:47)*
- [ ] ⏳ `[WIN-PLAY]` Every door opens and closes; closed doors block player and zombies
- [ ] ⏳ `[WIN-PLAY]` Walk from the safehouse to the grocery and pharmacy by both routes (street and back alley); roofs fade when entering
- [ ] ⏳ `[WIN-PLAY]` No getting stuck on walls, shelves, vehicles or doorways
- [ ] ⏳ `[VISUAL]` Buildings, doors and containers are readable; the alley and storeroom feel dark but zombie eyes show
- [ ] ⏳ `[WIN-PLAY]` FPS on Ashford Lane (HUD top-right): note it with the street, pharmacy and grocery in view

## Phase 6 — Noise & light
*Automated results (2026-11-08):* `[LINUX-AUTO]` 117/117 + both render tests passed. `[WEB-EXPORT]` headless Chrome (software GPU): F toggles the light, running logs a 120 px noise every ~0.45 s, rings and HUD meters draw, 0 errors. *Not proof of Windows or real-browser behaviour, and the FPS there is meaningless (software GPU).*
*Note:* the warehouse is behind the locked gate until Phase 7. For your play checks use the **pharmacy storeroom** (back of the pharmacy) and the **back alley**, which are dark and reachable.
- [x] ✅ `[LINUX-AUTO]` Walking past a zombie's back (60 px behind it) doesn't alert it; running does *(test_noise_light)*
- [x] ✅ `[LINUX-AUTO]` Running makes a 120 px noise every 0.4 s; walking makes none
- [x] ✅ `[LINUX-AUTO]` Darkness with the light off: zombie sight ×0.5; light on in darkness: ×1.5; no change in lit areas
- [x] ✅ `[LINUX-AUTO]` Battery: drains 1 s per second (180 s per battery), a spare battery is swapped in automatically, no battery = light goes out and can't be switched on
- [x] ✅ `[LINUX-AUTO]` Walls, crates, shelves and doors block light (occluders present)
- [x] ✅ `[LINUX-AUTO]` Noise rings only for the player's own noises ≥ 55 px; the meter fills on a gunshot and fades back to quiet
- [x] ✅ `[LINUX-AUTO]` Render test: warehouse interior dark, street brightness unchanged, flashlight lights the cone and is blocked by shelves *(flashlight_render_test: street 0.207/0.234 unchanged in all 4 captures; aisle dark 0.044; beam 0.320; behind shelf 0.044)*
- [x] ✅ `[WIN-AUTO]` `validate.bat` → ALL TESTS PASSED (117) *(your log, 08-11-2026 10:20; run without `render`)*
- [ ] ⏳ `[WIN-AUTO]` `validate.bat render` → RENDER TEST PASSED, FLASHLIGHT RENDER TEST PASSED
- [ ] ⏳ `[WIN-PLAY]` Walking past a zombie's back doesn't alert it; running does (watch the faint ring when you run)
- [ ] ⏳ `[WIN-PLAY]` A gunshot visibly pulls zombies from nearby streets (big ring, meter LOUD)
- [ ] ⏳ `[WIN-PLAY]` Entering the pharmacy storeroom never darkens the outdoor area
- [ ] ⏳ `[VISUAL]` Flashlight (F): cone follows the mouse, stops at walls/shelves/doors; LIGHT % goes down; no battery = no light; zombies still readable in the dark
- [ ] ⏳ `[WIN-PLAY]` FPS (HUD top-right) in the pharmacy storeroom with the flashlight on vs off
- [ ] ⏳ `[WIN-AUTO]` `validate.bat perf` → `logs/perf_benchmark.txt` now also has "Flashlight cost" rows (still needed for the Phase 3 30 FPS investigation)
- [ ] ⏳ `[WEB-EXPORT]` Lighting test: ≥ 45 FPS in Chrome, Edge and Firefox in the darkest, busiest area; light and shadow look the same as on Windows

## Phase 7 — Safehouse & objectives
*Automated results (2026-11-08):* `[LINUX-AUTO]` 128/128 + both render tests + scenarios (unchanged). `[WEB-EXPORT]` headless Chrome: walked to the stash, E opened it, Esc closed it, 0 errors. *Not proof of Windows or real-browser behaviour.*
- [x] ✅ `[LINUX-AUTO]` Delivering items updates objective progress exactly once (5 food + 3 water handed over from the stash; extra deliveries never complete it again)
- [x] ✅ `[LINUX-AUTO]` Full objective chain can be completed in a scripted run using only guaranteed items *(3 world seeds; ends with the radio broadcast)*
- [x] ✅ `[LINUX-AUTO]` "First aid" counts only medical items taken from pharmacy containers, including ones found before it became active
- [x] ✅ `[LINUX-AUTO]` Warehouse gate: refuses without bolt cutters; with them it opens (260 px noise), uses them up, stays open for the rest of the run and stops blocking zombie paths; a walkable path to the radio locker exists
- [x] ✅ `[LINUX-AUTO]` Stash: unlimited; full bag leaves the rest in the stash; **dying never touches the stash** *(Phase 5 death item re-checked)*
- [x] ✅ `[LINUX-AUTO]` Bed: full heal + new day; refused with a zombie within 200 px; respawn point is beside the bed
- [x] ✅ `[LINUX-AUTO]` Radio refuses before the last objective and uses nothing
- [x] ✅ `[LINUX-AUTO]` A missing quest item (still needed) is put back in its designated container, never duplicated
- [ ] ⏳ `[WIN-AUTO]` `validate.bat render` → ALL TESTS PASSED (128), RENDER TEST PASSED, FLASHLIGHT RENDER TEST PASSED
- [ ] ⏳ `[WIN-PLAY]` Objective chain plays start to finish; the next objective appears automatically (HUD line under KILLS, and the board next to the door)
- [ ] ⏳ `[WIN-PLAY]` Stash: store and take items; die with things in the stash and check they're still there
- [ ] ⏳ `[WIN-PLAY]` Sleep in the bed after getting bitten: full health, "Day 2"; try with a zombie at the window/door (refused)
- [ ] ⏳ `[WIN-PLAY]` Cut the warehouse gate: loud, zombies come; find the radio component with the flashlight; repair the radio and read the broadcast
- [ ] ⏳ `[VISUAL]` Safehouse furniture readable (stash, bed, radio desk, board); panels readable

## Phase 8 — UI
*Automated results (2026-11-08):* `[LINUX-AUTO]` 135/135 + both render tests + scenarios (unchanged). `[WEB-EXPORT]` headless Chrome: menu loads (Exit hidden in the browser), New game starts the game, Esc pauses, Esc resumes, walking works, 0 errors. *Not proof of Windows or real-browser behaviour.*
- [x] ✅ `[LINUX-AUTO]` Pause stops zombies, bites, healing, the flashlight battery and the survival timer; everything moves again after Resume
- [x] ✅ `[LINUX-AUTO]` Esc pauses only during normal play (not on the death screen, not on top of an open panel)
- [x] ✅ `[LINUX-AUTO]` Rebinding is saved and survives a restart (reload → T → E swap test, volume kept); secondary keys (I for the inventory) kept; tests always run with the default keys
- [x] ✅ `[LINUX-AUTO]` Main menu: New game target exists, Continue disabled (Phase 10), Exit hidden only in the browser, Settings and Credits open; credits contain the Godot licence notice
- [x] ✅ `[LINUX-AUTO]` Theme + original pixel font cover every character the UI uses; custom check boxes (no default Godot icons)
- [x] ✅ `[LINUX-AUTO]` Death screen shows time, kills and what was left in the backpack; FPS counter follows the setting
- [x] ✅ `[WIN-AUTO]` `validate.bat` → ALL TESTS PASSED (135) *(your log 08-11-2026 10:58; the run said VALIDATION FAILED only because of one-time import messages for the new theme files, fixed in Phase 9's validate.bat)*
- [ ] ⏳ `[WIN-AUTO]` `validate.bat render` → RENDER TEST PASSED, FLASHLIGHT RENDER TEST PASSED
- [ ] ⏳ `[WIN-PLAY]` Every button on every screen does what it says (main menu, settings, credits, pause, death screen, inventory, loot, stash, objectives)
- [ ] ⏳ `[WIN-PLAY]` Pause actually stops zombies and timers
- [ ] ⏳ `[WIN-PLAY]` Rebinding a key works and persists after restart (close the game, start it again, check the key)
- [ ] ⏳ `[WIN-PLAY]` Volume sliders change the sound; Fullscreen and V-Sync work (V-Sync off: note the FPS for the 30 FPS investigation)
- [ ] ⏳ `[VISUAL]` Readable at 1280×720 and 1920×1080, windowed and fullscreen

## Phase 9 — Art, animation, audio, licences
*Your Windows run (08-11-2026 11:20):* `[WIN-AUTO]` ALL TESTS PASSED (144). The log ends with both "VALIDATION PASSED" and "VALIDATION FAILED", which happens when two validate.bat windows run at the same time and write to the same log; no failing test or error line is in it. Please run it once more (one window) to get a clean verdict.
*Automated results (2026-11-08):* `[LINUX-AUTO]` 144/144 + both render tests + scenarios (unchanged). `[WEB-EXPORT]` headless Chrome: menu, New game, walking, firing the pistol with the new art and audio, 0 errors. *Not proof of how it looks or sounds on your PC: the `[VISUAL]` and `[WIN-PLAY]` items are yours.* Owner decisions: all assets original (made from code), "muted dusk, grim" mood.

**Artwork**
- [ ] `[VISUAL]` One consistent style: same pixel scale (16 px tiles, ~16×24 characters), palette and outline rules on every sprite
- [ ] `[VISUAL]` Player, each zombie type, items and interactables are readable against every floor type, in light and in darkness
- [x] ✅ `[LINUX-AUTO]` No scene, script or resource references a placeholder file (scan of every .tscn/.tres/.gd/.cfg); old placeholder files are excluded from exports (`*placeholder*` filter)
- [ ] `[VISUAL]` UI icons match the item list; no missing or default Godot icons

**Animation**
- [x] ✅ `[LINUX-AUTO]` Every required animation exists for player and zombies (idle, walk, run, melee, shoot, reload, hurt, death — plus shove for the player and attack for the Walker — in all 4 directions); no empty frames; the Walker's glowing eyes sit on the head in every frame; animations follow the player/zombie states
- [ ] `[VISUAL]` Animations loop without popping; direction changes look right; attack wind-ups are readable
- [ ] `[WIN-PLAY]` Animation timing matches gameplay timing (a swing hits when it looks like it hits)

**Sound**
- [x] ✅ `[LINUX-AUTO]` Every sound referenced from code exists; weapons have attack and hit sounds; music/ambience loops load (≥ 20 s); SFX and Music buses exist and the music slider controls the Music bus
- [ ] `[VISUAL]` (audio) Volumes balanced; gunshots loud but not clipping; distant vs. close zombie sounds distinguishable
- [ ] `[WIN-PLAY]` Music/SFX/master volume sliders work and persist
- [ ] `[WEB-EXPORT]` Audio starts after the first click, with no crackling in Chrome, Edge and Firefox

**Licence verification**
- [x] ✅ `[LINUX-AUTO]` Every image/sound file under `assets/` (and `icon.png`) appears in ASSET_LICENSES.md (scripted cross-check)
- [x] ✅ Manual: no external assets are used (everything is original, made from code; generators in `tools/asset_generators/`)
- [ ] ⏳ Manual: attribution text required by any licence is present on the in-game Credits screen (✅ Godot licence, Phase 8) and the itch.io page (Phase 12)
- [x] ✅ Manual: no paid assets

## Phase 10 — Save
*Automated results (2026-11-08):* `[LINUX-AUTO]` 151/151 + both render tests. `[WEB-EXPORT]` headless Chrome: New game saved at once, walking back into the safehouse saved, page reload → Continue enabled ("Day 1 - saved in the safehouse") → the game loads; 0 errors. **Browser note:** the browser stores the save a moment after it's written (measured 3–5 s in Claude's slow software-rendered browser; a reload sooner kept the previous save, never a damaged one).
- [x] ✅ `[LINUX-AUTO]` Save → load round-trip gives identical GameState (containers, backpacks with their quest item and exact position, stash, unlocks, objectives, taken-loot log, day, stats, flashlight battery)
- [x] ✅ `[LINUX-AUTO]` Full game round trip after dying outside: wake at the bed with 75 HP, bag empty, backpack (with the radio component) still out there, loaded rounds kept, stash, searched shelf, cut gate, dead zombie, open yard gate and objective progress all kept
- [x] ✅ `[LINUX-AUTO]` Corrupted or empty save → message, no crash; the file is kept as `.broken`; Continue disabled; New game offered
- [x] ✅ `[LINUX-AUTO]` Older save version is migrated (version 0 → 1); a newer version is rejected cleanly and left untouched
- [x] ✅ `[LINUX-AUTO]` Death triggers an immediate autosave
- [x] ✅ `[LINUX-AUTO]` Saves only at the safehouse (entering), the bed, quitting from the safehouse, on death and when a new game starts — never mid-expedition; writes are atomic (temp file, previous save kept as .bak until the swap succeeds, .bak used if a save was interrupted)
- [x] ✅ `[LINUX-AUTO]` Main menu: Continue enabled and focused with a save, shows the day; New game asks before replacing a save; tests use their own save file (your real save is never touched)
- [ ] ⏳ `[WIN-AUTO]` `validate.bat` → ALL TESTS PASSED (151) (`user://` = `%APPDATA%\Godot\app_userdata\LAST SIGNAL\`)
- [ ] ⏳ `[WIN-PLAY]` Quit mid-session, Continue → stash, objectives, looted containers, backpacks all correct
- [ ] ⏳ `[WIN-PLAY]` Die outside, close the game from the death screen, start again → Continue puts you at the bed with the backpack still out there
- [ ] ⏳ `[WEB-EXPORT]` In your browser: play, walk into the safehouse ("Game saved"), wait a few seconds, close the tab, reopen → Continue
- [ ] `[WEB-EXPORT]` **Save persistence across browser refresh:** save → press F5 in the browser → Continue restores stash, objectives, looted containers and backpacks
- [ ] `[WEB-EXPORT]` Same after closing the tab and reopening the game URL
- [ ] `[WEB-EXPORT]` If browser storage is unavailable or full (e.g. some private/incognito modes), saving fails gracefully: a clear "progress could not be saved" message, no crash

## Phase 11 — Optimisation & QA
*Automated results (2026-11-08):* `[LINUX-AUTO]` 152/152 + both render tests + playthrough bot + memory soak, VALIDATION PASSED. Difficulty scenarios S1–S6 unchanged (no AI or value changes). `[WEB-EXPORT]` headless Chrome: settings screen, new game, walking, flashlight on/off, pistol shot; 0 errors, 0 page errors (FPS 3–11 in Claude's software-rendered browser: not meaningful for real browsers).
- [x] ✅ `[LINUX-AUTO]` **Playthrough bot:** walks the real map from a new game to the ending (Stock up → First aid → Cut the lock → Signal parts → Last signal) on 5 world seeds, opening doors with E and searching containers: all 5 reach the ending (about 2.4 min of game time each). No stuck spots, no unreachable quest container
- [x] ✅ `[LINUX-AUTO]` Same bot with the normal Walkers (report only; the player can't die, simple bat + shove fighting): reached the ending, 0–8 bites, 6–11 kills over the runs so far
- [x] ✅ `[LINUX-AUTO]` **Memory soak:** 12 full sessions (menu, new game, shots, effects, death, respawn, save, Continue): object, node and resource counts identical after every session, 0 orphan nodes, memory +0.02 MB per session; a 5-minute session of shooting, shoving and flashlight use keeps a flat node count
- [x] ✅ `[LINUX-AUTO]` CPU: game logic for 40 Walkers in Ashford Lane = 0.8 ms per frame (wall clock), 80 Walkers = 1.9 ms. Rendering is the only real cost (breakdown in TECHNICAL_ARCHITECTURE §5)
- [x] ✅ `[LINUX-AUTO]` No one-time stutters on first flashlight, shot, blood, inventory or pause in software rendering (to be confirmed on your GPU)
- [x] ✅ `[LINUX-AUTO]` New setting **Flashlight shadows** (off = cheaper): applied at once, saved, visual only; in software rendering it halves the flashlight's cost (+6 ms → +3 ms)
- [ ] ⏳ `[WIN-AUTO]` `validate.bat` → ALL TESTS PASSED (152), PLAYTHROUGH PASSED, SOAK TEST PASSED, VALIDATION PASSED (**one window only**)
- [ ] ⏳ `[WIN-AUTO]` `validate.bat perf` → send `logs\perf_system.txt`, `perf_benchmark_opengl3.txt`, `perf_benchmark_opengl3_angle_quick.txt`, `perf_hitches.txt` (this decides the 30 FPS fix)
- [ ] ⏳ `[VISUAL]` Settings → "Flashlight shadows" off: the beam still works (now also through walls); FPS in the warehouse with the light on, shadows on vs off

### Windows QA pass — one session (about 45 minutes)
This one session covers every open `[WIN-PLAY]` item from Phases 4–10. Play from the editor (F5) with the FPS counter on; note FPS and memory (top right) at the start and the end. Mark each step ✅/❌ and write down anything odd.
1. **Menu & settings:** every button on the main menu; Settings → change volumes, Fullscreen, V-Sync off (note FPS later), Flashlight shadows; Controls → rebind Reload to T. Close the game, start it again: T still reloads, volumes kept.
2. **New game → street:** walk out of the safehouse, past a zombie's back (walking doesn't alert it; running does; faint ring when running). Roofs fade when you enter buildings; no getting stuck on walls, cars, shelves or doorways.
3. **Grocery + houses:** search shelves (bar, moving cancels, loot panel Take / Take all / Close); reopen a searched shelf (same items, "(empty)" darker look); fill the bag with scrap ("Bag full"). Inventory (Tab/I): descriptions, drop and pick back up.
4. **Home:** walking in says "Game saved". Stash: store food and water → Stock up done, next objective appears (HUD and board).
5. **Pharmacy:** go by the back alley this time; storeroom darkness never darkens the street; flashlight FPS on vs off. Get bitten, use a bandage (health rises over 3 s). First aid done.
6. **Death test:** let zombies kill you outside with items in the bag. Death screen; close the game from it. Start again → Continue → you wake at the bed with 75 HP; walk to your backpack and take everything back.
7. **Pickup truck → gate:** bolt cutters (can't be dropped); cut the warehouse gate (loud, zombies come); a gunshot pulls zombies from nearby streets.
8. **Warehouse:** dark; find the radio component with the flashlight; battery runs down and a battery swaps in.
9. **Home → bed → radio:** sleep after being bitten (full health, Day 2; refused with a zombie at the door). Repair the radio, read the broadcast.
10. **Pause & quit:** Esc pauses (zombies and timers stop). Quit to the menu from the safehouse, Continue: stash, objectives, looted containers and backpacks all as you left them.
11. **End:** note FPS and memory again. Memory should be about the same as at the start (a little higher is normal). Send Claude the notes and `logs\validate.log` / any errors from the Output panel.

## Phase 12 — Release
- [ ] `[WIN-PLAY]` 30-minute session with no crash and no memory growth trend (FPS counter shows memory when run from the editor)
- [ ] `[WIN-PLAY]` Windows .exe runs on a clean machine (no Godot installed)
- [ ] `[WEB-EXPORT]` Web build runs from itch.io in Chrome, Firefox and Edge
- [ ] `[VISUAL]` No placeholder art left in the release build
- [ ] ASSET_LICENSES.md lists every external asset; the credits screen matches it
