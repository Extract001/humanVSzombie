# Changelog

## [Unreleased]

### Fun pass (2026-11-08) — IMPLEMENTED + TESTED (automated); not yet VERIFIED
You said the game was boring: empty walking, zombies not scary, weak fighting, unclear goals. This pass targets all four.
- **More action:** the streets around you stay alive by day: about 10 zombies near you on day 1 (+1 each night), spawning out of sight; half of them come looking for you.
- **Lurchers:** a new fast zombie (reddish). It outruns you walking but not running, and dies faster (40 HP). 20% of street zombies, 25% of the night horde.
- **Fighting feels better:** a tiny freeze on every hit and a longer one on kills, big blood bursts, splats on the ground, a crunch sound, a red flash at the screen edges when you're hurt, and a heartbeat under 30 HP.
- **Score and streaks:** kills 10 points (Lurcher 20), multiplied by your streak (kills less than 4 s apart: x2 … x5, "x3 STREAK!" in big letters). Loot +2 per item, objectives +100, nights +50 × night. Score at the top right and in the dawn summary; **best score and most nights** on the main menu.
- **Where to go:** a cyan arrow with distance points to the next useful place: SEARCH (a container that has what you need), STASH, CUT (the gate), RADIO; at dusk an orange HOME, at home BOARD UP.
- **Faster pacing:** the day is 2.5 minutes (was 5), dusk 30 s (was 45), searches about 40% faster.
- Horde corpses are cleared at dawn. All zombie deaths count kills the same way.
- New original sounds: kill crunch, streak chime, heartbeat (`tools/asset_generators/make_audio_fun.py`).
- Tests: 169 (7 new in `tests/test_fun.gd`). Tests, bots and tools never write your best score and run without street spawns.

### Redesign Slice 1 — Day/night siege (2026-11-08) — IMPLEMENTED + TESTED (automated); not yet VERIFIED
New core loop chosen by you: scavenge by day, defend the safehouse at night (GDD §0).
- **Day/night cycle:** DAY 5 min (06:00–18:00) → DUSK 45 s → NIGHT 2.5 min → DAWN. Clock and phase at the top of the screen. Dusk turns the world orange, night dark blue; a warm lamp lights the safehouse. Outside at night counts as darkness (Walkers see you at half range; a lit flashlight gives you away).
- **Heat — "the town listens":** loud noises by day (gunshots +1, cutting a lock +0.5) raise Heat; the HUD shows "tonight: ~N of them". Resets at dawn.
- **Night siege:** the horde (4 + 1.5 per night + 0.75 per Heat, never more than 40 Walkers awake) walks in from 10 points at the map edges and attacks the safehouse **windows**. The front door can't be broken.
- **Windows & barricades:** three new safehouse windows (west, east, south). Press **E** to nail a plank (1 scrap, 1.2 s, max 3; moving cancels). Walkers crack and break planks; you can shoot and swing through the gaps, and they can reach through to bite you.
- **Dawn:** summary screen (horde size, kills, boards broken, yesterday's Heat), the horde leaves, 5 emptied containers in town get fresh loot (never quest containers), autosave.
- **Goal:** repair the radio and survive 10 nights → the convoy rescues you ("RESCUED"), then "Keep surviving". The radio broadcast now promises the convoy after the tenth night.
- **Bed:** full heal + sleep until dusk + save (the day now changes at dawn). Not at dusk or night.
- **Saving:** phase, clock, Heat, nights survived, boards and restocks are saved. A save made at dusk or night restarts at the start of dusk.
- New original sounds: boards hit/break/nailed, dusk bell, horde howl (`tools/asset_generators/make_audio_s1.py`).
- New tests: 10 (`tests/test_siege.gd`); the playthrough bot now also survives a real night; new `tests/scenarios/siege_scenarios.tscn` (part of `validate.bat scenarios`); `validate.bat perf` has night rows.
- Physics layer 6 "barricades", layer 7 nav-only; navigation layer 2 = window links (zombies only).

### Phase 11 — Optimisation & QA (2026-11-08) — IMPLEMENTED + TESTED (automated); not yet VERIFIED
- **Playthrough bot** (`tests/scenarios/playthrough_bot.tscn`): plays the whole game from a new game to the ending by walking the real map (doors, searches, stash, gate, radio) on 5 world seeds; plus a report-only run with the Walkers. All 5 seeds reach the ending. Now part of every `validate.bat` / `validate.sh` run.
- **Memory soak test** (`tests/perf/soak_test.tscn`): 12 full sessions + a 5-minute session; no leaks found (0 orphan nodes, identical object counts, flat node count). Part of every validation run.
- **Profiling:** game logic for 40 Walkers costs 0.8 ms per frame; rendering is the real cost (per-part breakdown in TECHNICAL_ARCHITECTURE §5). No AI, difficulty or gameplay values changed (scenarios S1–S6 identical).
- **New setting: Flashlight shadows** (Settings → Sound & display). Off = cheaper flashlight on weak graphics chips; the beam then shines through walls. Visual only. On by default.
- **FPS counter** also shows memory (`MEM n MB`) when run from the editor, for long play sessions.
- **`validate.bat perf` reworked** for the 30 FPS investigation (about 6 minutes): records your graphics chips, screen refresh rate and power plan (`perf_system.txt`); full benchmark (`perf_benchmark_opengl3.txt`, now with "Flashlight shadows off" rows); quick benchmark with the **ANGLE / Direct3D 11** driver (`perf_benchmark_opengl3_angle_quick.txt`); first-use stutter check (`perf_hitches.txt`). The old `perf_benchmark.txt` name is no longer written.
- Benchmark: `-- --quick` option; results file named after the graphics driver.
- QA checklist: Phase 11 results and a **one-session Windows QA pass** (about 45 minutes) that covers every open play-test from Phases 4–10.
- `validate.bat` / `validate.sh`: 4 steps now (import, tests, playthrough + soak, render).
- Tests: 152 (was 151): Flashlight shadows setting.

### Git (2026-11-08)
- Local repository created by the owner; first commit `ee5ad69` "LAST SIGNAL: Phases 0-10" (362 files) pushed to GitHub `Extract001/humanVSzombie`, branch `main`.
- `.gitignore`: added `__pycache__/` and `*.pyc` (asset generator scripts).
- README "Git" section rewritten: per-phase commit/push commands; roadmap Git workflow marked done.

### Phase 10 — Save system (2026-11-08) — IMPLEMENTED + TESTED (automated); not yet VERIFIED
- **Saving** (`SaveSystem` autoload, `save_v1.json` in `%APPDATA%\Godot\app_userdata\LAST SIGNAL\`; in the browser, the site's storage). The game saves when a new game starts, when you **walk into the safehouse** ("Game saved"), when you **sleep**, when you quit to the menu **from the safehouse**, and **immediately when you die** (quitting can't undo a death). Never mid-expedition: the pause menu says when quitting would lose progress.
- **What's saved:** everything in your bag, loaded rounds, current weapon, health (or "dead" → you wake at the bed with 75 HP), every searched container, dropped piles and **death backpacks** (with exact positions and quest items), the stash, unlocks (the cut gate), objective progress, the day, kills/deaths/time, the flashlight battery, which zombies are dead (they stay dead) and which doors are open. Living zombies go back to their starting spots.
- **Continue** in the main menu (enabled when there's a save, shows e.g. "Day 3 - saved after sleeping"). **New game** asks before replacing a save.
- **Safety:** desktop saves are written to a temp file, checked, then swapped in (the old save is kept as `.bak` until the swap succeeded; reading falls back to it). A damaged or empty save never crashes the game: you get a message, the file is kept as `.broken`, and you can start a new game. Saves from an older format are upgraded (version 0 → 1); saves from a newer version are refused and left untouched.
- **Browser:** saves survive a page reload (tested). The browser stores the save a moment after it's written (3–5 s in Claude's slow test browser), so wait a couple of seconds after "Game saved" before closing the tab. One direct write there (instead of temp + rename) so it's stored in one go.
- Tests, the benchmark and the scenarios use their own save files: your real save is never touched by `validate.bat`.
- **Tests:** 151 automated checks (was 144): world round trip, full game round trip after a death, damaged/empty/incomplete saves, migration and newer-version refusal, safe replacement + .bak fallback, autosave points (and no mid-expedition saves), Continue/New game in the menu.

### Phase 9 — Art, animation, audio (2026-11-08) — IMPLEMENTED + TESTED (automated); not yet VERIFIED
Owner decisions: all assets original (made by Claude from code, no downloads, no purchases); mood "muted dusk, grim".
- **New tileset** (same 14 tiles, so the map is unchanged): textured asphalt with worn lane markings, sidewalk slabs, grass, stained concrete, wood planks, brick walls, crates, shingled roofs, stocked shelves, counters, fences, tiled floors, dirt.
- **Characters:** new survivor and Walker sheets with outlines and a soft ground shadow. Survivor animations: idle, walk, run, melee, shoot, reload, hurt, shove, death; Walker: idle, walk, attack (the bite wind-up), hurt, death; all 4 directions. The game picks them from the player/zombie state (visual only). Deaths now play a fall animation instead of rotating the sprite.
- **Props:** new vehicles, containers, backpack and item pile, safehouse furniture, 10 item icons, weapons, game icon.
- **Effects:** muzzle flash, blood spray on hits, dust and sparks where bullets hit walls.
- **Sound:** improved pistol, zombie grunt/death, player hurt, hits; new footsteps (player walk/run, zombie shuffle near you), distant zombie groans, UI clicks on every button.
- **Ambience + music** (original, Ogg loops): wind and city rumble outside with a tense drone/heartbeat score; rain on the roof and a calm score in the safehouse and the main menu; 2.5 s crossfades. New **Music volume** slider (Music bus).
- HUD: the "PROTOTYPE - PLACEHOLDER ART" banner is gone; shorter controls line (it overlapped the ammo counter).
- **Asset generators** are included in `tools/asset_generators/` (Python) so every asset can be regenerated; checked: they reproduce the shipped files byte for byte.
- Old placeholder images are no longer used and are **excluded from exported builds** (`*placeholder*` export filter). They can be deleted from your folder (list in ASSET_LICENSES.md); I didn't delete anything.
- **Fix:** cosmetic randomness (footsteps, sound pitch, groans) now uses its own random generator; at first it shifted the seeded zombie test's dice and made it fail.
- **Fix — your Windows run at 10:58 said VALIDATION FAILED although all 135 tests passed.** Cause: on the first import after new files arrive, Godot loads the project theme before its font and icons are imported and prints "ERROR: Failed loading resource" once; `validate.bat` counted those lines. Reproduced here from a fresh import. `validate.bat`/`validate.sh` now run the import twice (the first pass goes to `logs/import.log` and isn't counted; the second must be clean). The game itself was not affected.
- **Tests:** 144 automated checks (was 135): no placeholder references, every animation present and drawn, eye overlay alignment, animations follow states, muzzle flash, blood on hits, audio files/buses/music slider, soundscape mood, licence cross-check, every sound used by code exists.

### Phase 8 — UI & game flow (2026-11-08) — IMPLEMENTED + TESTED (automated); not yet VERIFIED
- **Main menu** (new start scene): New game, Continue (disabled until saving in Phase 10), Settings, Credits, Exit (hidden in the browser, where a page can't close itself).
- **Pause menu (Esc):** Resume, Settings, Controls, Main menu. Pausing really stops the game: zombies, bites, healing, the flashlight battery, timers and the survival clock. Esc doesn't pause on the death screen or on top of an open panel (it closes the panel instead).
- **Settings** (saved to `settings.cfg`, applied at start): master and effects volume, fullscreen, V-Sync (useful for the 30 FPS investigation), FPS counter on/off, and **key rebinding** for 13 actions. Click a key, press the new one (Esc cancels); a key already used by another action is swapped, so nothing is left unbound. "Reset controls to default".
- **Death screen:** time survived, zombies killed, what was left in the backpack (kinds and total), Respawn / New game / Main menu.
- **Look:** a project-wide theme in the "field notebook / tape label" style (dark panels, tan borders, tape-yellow accents and focus outlines, custom check boxes and sliders) and an **original pixel font** (5×7 glyphs, drawn for this project; it replaces Godot's default font everywhere). All existing screens (HUD, inventory, loot, stash, objectives, ending) use it.
- **Credits** include the Godot Engine licence text and its third-party component list (required for distributed builds).
- **Audio:** sounds now play on an "SFX" bus so the effects slider works.
- **Test robustness:** navigation-readiness waits in 4 older tests raised to 5 s (the navigation server took > 2 s under CPU load in one full run; only the waiting changed, not the checks). Tests always run with default key bindings, whatever you saved.
- **Tests:** 135 automated checks (was 128).

### Phase 7 — Safehouse & progression (2026-11-08) — IMPLEMENTED + TESTED (automated); not yet VERIFIED
- **Objective chain** (GDD §11), shown on the HUD under KILLS and on the board in the safehouse:
  1. *Stock up*: put 5 food + 3 water in the stash (they're handed over when complete).
  2. *First aid*: take 2 medical items from pharmacy containers.
  3. *Cut the lock*: bolt cutters from the pickup truck bed, used on the warehouse gate.
  4. *Signal parts*: the radio component from the warehouse office locker.
  5. *Last signal*: repair the radio at the desk → an original broadcast reveals an evacuation route; "Keep playing" continues the game.
  Each objective is data (`data/objectives/*.tres`) checked against the game state, so progress made early still counts, and nothing completes twice.
- **Safehouse furniture:** stash (unlimited, safe when you die; Store / Store all / Take / Take all), bed (full heal, new day; refused with a zombie within 200 px; you respawn beside it), radio desk, objective board.
- **Warehouse gate:** "Cut the chain" with bolt cutters. Loud (260 px, wakes the warehouse), uses the cutters up, stays open for the rest of the run, and zombies can path through it afterwards.
- **Quest-item safety net:** if a still-needed quest item exists nowhere (bag, stash, containers, piles, backpacks), it's put back in its designated container (runs at start; Phase 10 runs it after loading).
- **Not in this phase:** saving at the bed (Phase 10), zombie population refresh on a new day (later), weapon rack (no extra weapons yet).
- **Test fix:** the Phase 3 test "chase follows the player around a corner" failed about 1 run in 8 (also on the Phase 4 and 5 code: measured 2/25 and 4/25). The cause is intended randomness: a searching zombie looks around in random directions and sometimes misses you. The test now fixes the random seed (0/25 failures). No game code changed for this.
- Phase 6 `[WIN-AUTO]` 117/117 (your log, 10:20) recorded in the QA checklist. Your Git name/e-mail edit in README.md is kept.
- **Tests:** 128 automated checks (was 117), including a scripted run of the whole chain using only guaranteed items, on 3 world seeds.
- **Art/audio (original placeholders):** safehouse furniture sprites, chain-cut and radio sounds.

### Phase 6 — Noise & light (2026-11-08) — IMPLEMENTED + TESTED (automated); not yet VERIFIED
- **Running is loud, walking is silent:** running makes a 120 px noise every 0.4 s. You can walk past a zombie's back; running past it makes it turn.
- **Noise rings:** your own noises of 55 px or more draw a ring in the world that grows to the noise radius and fades (faint for running/searching, strong for gunshots). Drawn unshaded, so they show inside dark rooms too. Zombie groans and door bangs don't draw rings.
- **HUD noise meter** (bottom-left): fills with your loudest recent noise (quiet / low / medium / LOUD) and fades back.
- **Flashlight (F):** a cone of light that follows your aim. Walls, crates, shelves and doors block it (real shadows). It lights the floor inside dark interiors without touching the street.
- **Batteries:** a new run starts with a full battery in the flashlight (3 minutes of light). When it runs out, a spare battery from your bag is put in automatically; with no spare the light goes out ("Flashlight battery is dead"). HUD shows LIGHT on/off, % and spare count. The flashlight is equipment, so it stays with you when you die (spare batteries in the bag go into the backpack).
- **Light changes how far zombies see you:** in a dark area with the light off, zombie sight is halved (80 px); with the light on, it's ×1.5 (240 px). Lit areas are unchanged (160 px). Values are in `ZombieData`.
- **Fix:** respawn health now comes from `PlayerStats.respawn_health` (75) instead of a duplicate constant in `game.gd`.
- **Tests:** 117 automated checks (was 110), plus a second render test (`flashlight_render_test`): in the real warehouse the aisle is dark (0.044), the beam lights the floor (0.320), the floor behind a shelf stays dark (0.044), and the street is identical in every capture. `validate.bat render` now runs both render tests.
- **Benchmark:** `validate.bat perf` has new "Flashlight cost" rows (warehouse and street, light on/off).
- **Measured on Claude's software GPU (not your laptop):** the flashlight costs about 4 ms of drawing per frame (about 2 ms for the light, 2 ms for its shadows). Real GPUs are usually much faster at this, but given the 30 FPS you reported in Phase 3, this needs your `validate.bat perf` numbers.
- **Difficulty scenario S5** (dark room, 5 Walkers, no flashlight) changed because zombies now see half as far in the dark: damage 12 / 72 / 12 over 3 seeds (was 48 / 48 / 60). Other scenarios unchanged.
- **Art/audio (original placeholders):** flashlight cone texture, flashlight click.

### Phase 5 — Loot & inventory (2026-11-08) — IMPLEMENTED + TESTED (automated); not yet VERIFIED
- **Items** (`data/items/*.tres`, `ItemData` + `ItemRegistry`): canned food, water, bandage, medicine kit, pistol rounds, shotgun shells, scrap, battery, and the quest items bolt cutters and radio component. Each has a stack size, description and icon.
- **Inventory:** 12 slots, each holding one item type up to its stack size (e.g. 5 bandages, 48 pistol rounds). `add_item` returns what didn't fit, so nothing is ever lost; counts never go negative. Same API as before, so weapons and reserve ammo work unchanged. You start with 16 pistol rounds and 2 bandages.
- **Searching containers:** press E on a container and stand still for its search time (shelves 0.8 s, counter 1.0 s, cabinets/lockers/boxes 1.2 s, car trunks 2.0 s). Rummaging makes a 60 px noise. Moving, attacking, reloading, shoving, switching weapons or being hit cancels it, and you get nothing. Searching is a timer, not a new player state, so the verified state machine is unchanged. A progress bar shows under the player.
- **Loot is rolled once** per container (seeded per world + container id), then remembered in the new **GameState** autoload. Reopening never re-rolls or duplicates. Searched-and-empty containers look darker.
- **Loot tables** (`data/loot_tables/*.tres`) per container type, with empty chances; quest items never come from random tables.
- **Guaranteed quest items** (`data/objectives/quest_guarantees.tres`): 7 food + 5 water in the grocery shelves 01–04 and two kitchens, 4 medical items in the pharmacy, bolt cutters in the pickup truck bed, radio component in the warehouse office locker. Always added on top of the random roll.
- **Loot panel:** Take, Take all (E), Close. If your bag is full, the rest stays in the container ("Bag full"). Walking away closes it.
- **Inventory panel** (Tab or I): slots, description, Use, Drop. Bandage heals 25 over 3 s, medicine kit heals 60; using at full health is refused and consumes nothing. Dropping creates an item pile on the floor (quest items can't be dropped or used up).
- **Death backpack (in-session):** on death, everything in the bag goes into a backpack at the death spot, moved onto the walkable area so it's never inside a wall. Equipped weapons and the rounds loaded in them stay with you. Quest items go in the backpack too. Several backpacks can exist; each disappears once emptied. HUD arrow shows the direction and distance (m) to the nearest one.
- **Death screen:** "Respawn at safehouse" (75 HP, full stamina, NORMAL state, at the bed corner; the bed itself comes in Phase 7) or "New game". Saving the backpack to disk (autosave on death) is Phase 10.
- **Art/audio (original placeholders):** 10 item icons, backpack and item-pile sprites, 3 sounds (search rustle, pickup, use item).
- **Tests:** 110 automated checks (was 88). New: stacking, full bag, never negative, starting items, healing, quest items not droppable/usable, piles, search timing + noise, cancel by move/hit/attack/shove grants nothing, no duplication on reopen, full bag leaves the rest, seeded rolls, guaranteed items over 1,000 seeds, guarantee totals, loot tables only use known items, loot/inventory panels in the real game, death backpack contents, backpack on navigation, two backpacks + quest items recovered, respawn at 75 HP.
- **Fixed during development:** Tab didn't close the inventory in the browser after clicking a button (Tab is also the UI's focus key); the panels now read their keys before the UI does. Static data caches are released at exit (no leak warnings).
- Phase 4 `[WIN-AUTO]` 88/88 (your log, 02:47) recorded in the QA checklist.

### Phase 4 — Exploration & environment (2026-11-08) — IMPLEMENTED + TESTED (automated); not yet VERIFIED
- **Ashford Lane** (`scenes/world/ashford_lane.tscn`, 160 × 86 tiles), one continuous scene. It is now the game's start map (`game.tscn` → World/Map).
  - Safehouse with fenced yard and gate; houses A, B, C; grocery store (3 shelf rows, checkouts, back door); pharmacy (shop floor, counter, dark storeroom, back door).
  - Main and residential streets, two cross streets, dark back alley, parking lot, 11 vehicles.
  - Warehouse (dark, back office) behind a **locked chained gate** ("needs bolt cutters", Phase 7). Police checkpoint behind a **wrecked bus** (post-MVP).
  - 23 Walkers placed per the GDD (largest group at the pharmacy; 3 dormant behind the warehouse gate).
- **Interaction system:** `Interactable` component (physics layer 5). The player's Interactor picks the nearest interactable **in reach and in front** (~78°). HUD prompt `[E] Open door`; pop-up messages for location names and "It's locked."
- **Doors & gates** (`door.tscn`): open/close with E (creak/thud sounds, 40 px noise). Closed doors block movement, bullets, sight and light. A door won't close on someone standing in it. Locked doors/gates can't open; `unlock()` rebakes navigation (Phase 7 hook).
- **Roofs** (`roof.tscn`): cover building interiors (walls and doors stay visible). They fade out when you step inside and show the location name.
- **Loot containers** (`loot_container.tscn`): 30 placed with unique ids and types, including all 11 designated quest containers. Phase 4 only says "searching arrives in Phase 5".
- **Vehicles** (`vehicle.tscn`): car, pickup, bus; solid and cut out of the navigation mesh.
- **Zombies:** bang on closed doors (sound every 1.5 s, can't open or break them). Give up investigating an unreachable noise after 12 s.
- **Navigation:** bake is deferred until the whole level has loaded (vehicles and locked gates register first). Doors are deliberately not in the mesh, so paths go through doorways.
- **Art/audio (original placeholders):** 6 new tiles (roof, shelf, counter, fence, tiled floor, dirt), vehicles, container markers (pharmacy cabinet uses a **green** cross: the red-cross emblem is legally protected), 4 door sounds.
- **Tests:** 88 automated checks (was 78). New: map bounds/spawn/container ids, Walkers not inside walls, routes and their lengths, locked gate blocks paths until unlocked, doors block/allow, door won't close on a player, zombies bang on doors, prompt range + facing, roof fade + location name, map light budget. Benchmark now also measures the real game map.
- **Fixed during development:** a change that kept zombies chasing a ghost after losing sight was reverted (it altered verified Phase 3 search behaviour; caught by the existing tests). Test target inside a shelf corrected.

### Phase 3 test results + performance investigation (2026-11-08)
- QA_CHECKLIST: recorded your Phase 3 results. All behaviour checks pass (Linux 78/78, Windows 78/78, manual play, arenas balanced, browser). **Performance: 30 FPS vs. the 60 FPS target → Phase 3 NOT VERIFIED.**
- Investigation so far: no frame-rate cap in the project (max_fps 0, V-Sync on = locked to the screen refresh rate). Walker AI and physics cost ~1.2 ms per frame for 40 Walkers. 2D lighting is the largest drawing cost in Claude's (software-GPU) measurements.
- New: `tests/perf/perf_benchmark.tscn` + `validate.bat perf`. Measures FPS, frame times, physics+AI, render CPU/GPU, draw calls; 1/10/20/40 Walkers × yard/dark room × V-Sync on/off, plus lights on/off. Writes `logs/perf_benchmark.txt`.
- No gameplay code changed (no optimization before the bottleneck is identified on your laptop).

### Phase 3 — Zombie intelligence (2026-11-08) — IMPLEMENTED + TESTED (automated); not yet VERIFIED
- **NoiseSystem** autoload: `emit_noise(position, radius, source)`. Zombies in range hear it; a wall in between halves the radius; runs only when a noise happens. Pistol shots (480 px), bat swings (90 px) and shoves (50 px) now make noise.
- **Zombie AI states:** IDLE → WANDER (short strolls within 80 px, 2–5 s pauses) · INVESTIGATE (walks to a heard noise) · SEARCH (looks around in new directions every second for 6 s, then gives up) · CHASE · ATTACK · STUNNED · DEAD. Zombies settle where they end up, so noise slowly moves hordes.
- **Pathfinding:** `NavigationBaker` builds the walkable mesh from wall/prop tiles when the level loads (about 2 ms; keeps 6 px from walls). Zombies follow paths around walls when they can't see you, and go straight at you when they can. Before the map syncs (~0.2 s) they walk straight.
- **Group behaviour:** a zombie that spots you groans (140 px noise); nearby zombies come to investigate. Hearing a groan never causes another groan (no endless chain reactions).
- **Performance:** staggered 0.2 s thinking; calm zombies farther than 700 px go dormant (think once per second, don't wander); path recalculated at most every 0.25 s.
- **Difficulty measurement:** six arenas (S1–S6) with scripted player bots, run 3 times each, plus a 40-zombie performance run (`tests/scenarios/`, `validate.bat scenarios`). Playable versions: `scenes/debug/arena_playground.tscn` (F1–F6). Debug content is excluded from exported builds.
- **Player:** `move_override` hook (test bots now, on-screen joystick later).
- **Tests:** 78 automated checks (was 66), including noise radius, wall damping, pathing around walls, following around corners, search/look-around, wandering, group alert, no groan chain reactions, gunshot range, dormant mode, navigation mesh coverage, all arenas buildable.
- **Fixed during testing:** wandering zombies in a scene without a navigation mesh picked (0,0) as their target and never moved; tests now wait for the navigation map to finish syncing.
- Browser diagnostics (`?perf` only): state changes, reloads and bites are logged to the browser console.

### Phase 2 status update (2026-11-08)
- `[WIN-AUTO]` 66/66 passed on the owner's Windows Godot 4.7.2; `[WIN-PLAY]` reported as passed by the owner → **Phase 2 VERIFIED**.

### Phase 2 — Combat (2026-11-08) — IMPLEMENTED + TESTED (automated); not yet VERIFIED
- **Weapon framework:** `WeaponData` resource (melee / hitscan; damage, cooldown, commitment time, range, arc, knockback, magazine, reload, spread, pellets, ammo type, noise radius, sounds). `data/weapons/bat.tres` (25 dmg, 0.6 s, 100° arc, 28 px) and `pistol.tres` (34 dmg, 3 shots/s, 8 rounds, 1.2 s reload, 4° spread, 320 px).
- **WeaponHolder:** 2 slots (bat, pistol), per-slot magazines, reserve ammo only in the inventory, **atomic reloads** (cancelled reloads move nothing), switching (1 / 2 / mouse wheel, 0.2 s draw time), auto-reload on empty, dry-fire click, hitscan rays (stopped by walls), melee cone hits with wall checks, tracers, muzzle flash light, camera kick.
- **Inventory core** (`scripts/inventory/inventory.gd`): item counts; starts with 16 pistol rounds. Slots/capacity come in Phase 5 on the same API.
- **Player state machine** fully active: NORMAL / ATTACKING / RELOADING / SHOVING / HURT / DEAD with the transition rules from TECHNICAL_ARCHITECTURE §4.3. Damage still never depends on state. HURT only for hits ≥ 25 (Walker bites don't stun-lock).
- **Quick shove (Space):** 120° / 36 px cone, pushes every zombie in it about 25 px, 0.6 s stagger, 2 damage, 15 stamina (refused below 15), 1.0 s cooldown, restarts the stamina regen delay, cancels a reload with no ammo change, no invincibility.
- **Zombie reactions:** hit flash, knockback, 0.15 s hit stun that interrupts bite wind-ups, turns toward the attacker, `shove_resistance` support (Brute later), death once (corpse stays visible, no collision, can't be hit again), grunt when it first spots you, death sound.
- **HUD:** weapon slot + name, magazine / reserve (amber when low, red when empty), reload progress bar, kill counter. Crosshair replaces the mouse cursor in play. Game-over screen shows zombies defeated.
- **Audio:** `AudioManager` autoload (pool of 16 positional players). 10 original synthesized placeholder sound effects.
- **Test yard:** 5 Walkers (one inside the dark room).
- **Tests:** 66 automated checks (was 37), including 1,000 random fire/reload/switch/cancel sequences that conserve ammo, fire-rate spam, shove cone/stagger/regen, illegal state transitions, sounds requested, corpse visibility.
- **Fixed during testing:** (1) corpses were drawn under the ground tiles and vanished; (2) sounds played in headless test runs leaked memory (the "Dummy" audio driver never frees them), so the AudioManager now only announces sounds when there is no audio output.

### Phase 1 — Playable prototype (2026-11-08) — IMPLEMENTED + TESTED (automated); not yet VERIFIED
- Godot project (`project.godot`): Compatibility renderer, 640×360 pixel-perfect viewport (integer scaling, window 1280×720), nearest filtering, pixel snapping, named physics/light layers, full input map (all planned actions; WASD/Shift/mouse used now).
- Data resources: `PlayerStats` (`data/player/player_stats.tres`), `ZombieData` (`data/zombies/walker.tres`) with all GDD values.
- Components: `HealthComponent` (no invincibility; damage independent of state), `Hurtbox`.
- Player: walk 80 / run 140 px/s, acceleration 900 / friction 1200, normalized diagonals, stamina (drain 20/s, regen 15/s after 1 s, min 10 to start running), mouse facing, 4-direction placeholder animation, damage flash + camera shake, death, full state enum (NORMAL…DEAD; combat states used from Phase 2).
- Walker: staggered 0.2 s think tick; sight (160 px, 110° cone, 24 px proximity, wall raycast); CHASE at 45 px/s; bite 12 damage, 0.4 s telegraphed wind-up, ≥ 1.2 s between bites; SEARCH last known position for 6 s (always times out, even if blocked); unshaded eyes.
- Test yard map (60×40 tiles, TileMapLayer): safehouse with doorway, road, L-shaped wall, crates, **dark room using local Subtract-light darkness** (walls excluded, faint player glow only inside darkness).
- HUD (health, stamina with "can't run" grey state, FPS, "in darkness", placeholder notice) and game-over screen with time survived and Retry.
- Tests: headless runner with 37 automated checks + darkness render test; `tools/validate.sh`, `tools/validate.bat` (Windows), `tools/serve_web.bat`.
- Export presets: Web (single-threaded, no special server headers) and Windows Desktop. Automated browser load test passed in headless Chrome.
- Original placeholder art: tiles, survivor, Walker, Walker eyes, icon.
- Fix found during testing: a searching Walker blocked by a wall would never give up; search now always ends after 6 s.

### Phase 0 — Planning (2026-11-08)
- Confirmed engine: Godot 4.7.2-stable (Windows editor; same version used headless for automated validation).
- Added GDD, Technical Architecture, Development Roadmap, QA Checklist.
- Added README, CLAUDE.md, ASSET_LICENSES.md, .gitignore.

### Phase 0 — Revision v0.2 after owner review (2026-11-08)
- GDD: quick shove spec; recoverable death backpack rule; full Walker values; player acceleration/feedback values; starting loadout; map structure, size correction (160×100 tiles), routes safehouse ↔ grocery ↔ pharmacy; Phase 1 test yard; decision log.
- Architecture: backpack and shove design; four labelled test categories (LINUX-AUTO / WIN-PLAY / WEB-EXPORT / VISUAL); web export pipeline (single-threaded build); Git safety rules.
- Roadmap: Phase 0 status corrected (documents completed; review + approval pending); minimal web export moved into Phase 1; browser lighting tests in Phase 6; shove in Phase 2, backpack in Phase 5/10.
- QA checklist rewritten with test-category labels and new checks for shove, backpack, Phase 1 web build.
- README: Git setup commands for the owner.

### Phase 0 — Revision v0.3 after second owner review (2026-11-08)
- Lighting: replaced the incorrect whole-canvas `CanvasModulate` interior darkness with local Subtract-mode `PointLight2D` darkness per interior + `Area2D` for gameplay; roofs excluded via light cull masks; unshaded zombie eyes. Proof-of-concept render test added (`documentation/research/`), 6/6 checks passed `[LINUX-AUTO]`.
- Player: `SHOVING` added to the state enum; full transition table; damage independent of state (no invincibility); heavy-hit-only HURT; atomic reloads.
- Quests: `guaranteed_items` on containers; designated containers for food/water, medical, bolt cutters, radio component; quest items undroppable; load-time respawn safeguard; automated guarantee tests.
- Walker: values unchanged; added difficulty test plan (6 automated scenarios + matching playable arenas); container search times added to the GDD.
- QA: new `[WIN-AUTO]` category for validate.bat; added tests for run stamina minimum, regen after shove, 75 HP respawn, quest items in backpack, quest guarantees, weapon-switch ammo conservation, browser-refresh save persistence, full Phase 9 art/animation/audio/licence verification.
