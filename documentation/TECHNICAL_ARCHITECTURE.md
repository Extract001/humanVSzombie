# LAST SIGNAL — Technical Architecture

Version 0.3 (revised 2026-11-08 after second owner review; approval pending) · Engine **Godot 4.7.2-stable** (Windows editor `C:\Al-am\Game_engine\Godot_v4.7.2-stable_win64.exe`) · Language **GDScript only**

---

## 1. Engine & project settings

| Setting | Value | Why (plain language) |
|---------|-------|----------------------|
| Renderer | **Compatibility** (`gl_compatibility`) | The only renderer Godot 4.7 can run in a web browser (WebGL 2.0). It also runs well on your Ryzen laptop and on low-end PCs. 2D lights and shadows work with it. |
| Base resolution | 640 × 360 | Pixel-art "canvas". Scaled up crisply to 1280×720, 1920×1080. |
| Stretch | `mode = viewport`, `aspect = keep`, integer scaling | Keeps pixels square and sharp, no blurry half-pixels. |
| Default texture filter | Nearest | Crisp pixel art. |
| Physics | Godot 2D physics (default) | Built-in, free, enough for top-down. |
| Physics tick | 60 Hz | Standard. |
| Tile size | 16 × 16 px | Small enough for detail, big enough for a solo artist. |

## 2. Folder structure (created only when a phase needs it)

```
Game_development/            ← Godot project root (project.godot lives here)
├── project.godot  README.md  CLAUDE.md  CHANGELOG.md  ASSET_LICENSES.md
├── scenes/
│   ├── main/        game.tscn (gameplay root), main_menu.tscn
│   ├── player/      player.tscn
│   ├── zombies/     walker.tscn (one zombie script; each type is a scene + ZombieData .tres)
│   ├── weapons/     weapon_holder.tscn, tracer.tscn
│   ├── world/       test_yard.tscn (Phase 1), ashford_lane.tscn, door.tscn, loot_container.tscn,
│   │                dark_zone.tscn, death_backpack.tscn
│   ├── safehouse/   stash.tscn, radio_desk.tscn, bed.tscn
│   └── ui/          hud.tscn, inventory_ui.tscn, pause_menu.tscn, death_screen.tscn
├── scripts/
│   ├── autoload/    event_bus.gd, game_state.gd, noise_system.gd, save_system.gd, audio_manager.gd
│   ├── components/  health_component.gd, hitbox.gd, hurtbox.gd, interactable.gd
│   ├── player/  zombies/  weapons/  inventory/  world/  ui/
│   └── data/        item_data.gd, weapon_data.gd, zombie_data.gd, loot_table.gd, objective_data.gd
├── data/            *.tres files (the actual numbers): items/, weapons/, zombies/, loot_tables/, objectives/
├── assets/          sprites/, tiles/, audio/sfx, audio/music, fonts/, ui/
├── tests/           test_runner.tscn + test_*.gd (headless runner, no plugin) · render/ (render tests)
├── tools/           validate.bat (one-click check on Windows), validate.sh (Linux/CI), serve_web.bat
│                    research/ is under documentation/ (spikes, screenshots — no game code)
├── export_presets.cfg   Windows Desktop + Web presets (Phase 1)
├── export/          build output, git-ignored: export/web/, export/windows/
└── documentation/   GDD.md, TECHNICAL_ARCHITECTURE.md, DEVELOPMENT_ROADMAP.md, QA_CHECKLIST.md
```

Scripts live next to their purpose, not in one giant `scripts/` dump. The `scenes/` and `scripts/` split is kept because you asked for it, and it makes "where's the logic?" easy for a beginner.

## 3. Autoloads (global singletons). Kept to five.

| Autoload | Job | Size target |
|----------|-----|-------------|
| `EventBus` | Signals only, no logic: `player_died`, `item_collected(id, qty)`, `zombie_killed(type)`, `objective_updated`, `noise_emitted(pos, radius, source)` | ~30 lines |
| `GameState` | The current run: stash contents, looted container IDs, unlocked areas, objective progress, stats (kills, time) | ~150 lines |
| `NoiseSystem` | `emit_noise(position, radius, source)` → notifies zombies in range | ~80 lines |
| `SaveSystem` | Converts `GameState` to and from JSON in `user://save_v1.json` | ~120 lines |
| `AudioManager` | Small pool of `AudioStreamPlayer2D`s, plays SFX without spawning nodes every shot | ~80 lines |

**Rule:** autoloads never reference scene nodes directly. Scenes talk to them; they answer through signals.

*Status (Phase 3):* `AudioManager` and `NoiseSystem` exist. `AudioManager` It emits `sound_requested` for every sound (used by tests) and only plays audio when a real audio driver is present: Godot's headless "Dummy" driver never frees finished sounds. `NoiseSystem.emit_noise()` notifies `noise_listeners` directly and also emits `noise_emitted` (HUD meter and rings in Phase 6). `EventBus`, `GameState` and `SaveSystem` are added in the phases that need them (no empty managers).

**Physics layers:** 1 world (walls, props) · 2 player body · 3 zombie bodies · 4 hurtboxes (zombie hit areas, used by rays and melee) · 5 interactables (Phase 4).
**Light (render) layers:** 1 default · 2 interior darkness (see §4.6).

## 4. Key design patterns

### 4.1 Data-driven content with Godot Resources
Each kind of content has a small script that defines its fields (`class_name ItemData extends Resource`). The actual items are `.tres` files you can edit in the Godot Inspector with no code.

```gdscript
# scripts/data/weapon_data.gd
class_name WeaponData extends Resource
@export var id: StringName
@export var display_name: String
@export_enum("melee", "hitscan") var kind := "hitscan"
@export var damage := 34.0
@export var fire_rate := 3.0          # shots per second
@export var magazine_size := 8
@export var reload_time := 1.2
@export var range_px := 320.0
@export var spread_deg := 4.0
@export var pellets := 1
@export var ammo_item_id: StringName = &"ammo_pistol"
@export var noise_radius := 480.0
```
Adding a new gun = new `.tres` file plus a sprite. No combat code changes.

### 4.2 Components instead of giant scripts
Small reusable nodes attached to scenes:
- `HealthComponent`: `max_health`, `take_damage()`, `heal()`, signals `damaged`, `died`. Used by player **and** zombies.
- `Hurtbox` (Area2D): "I can be hit." `Hitbox` (Area2D): "I deal damage" (melee swings, zombie bites).
- `Interactable` (Area2D): shows a prompt, emits `interacted(by)`. Used by doors, containers, stash, bed, radio.

### 4.3 Player
`CharacterBody2D` + `AnimatedSprite2D` + `HealthComponent` + `Interactor` + `WeaponHolder` + `Camera2D` (smoothing on).
Movement uses `velocity.move_toward(target, accel * delta)` for quick but not twitchy movement, with diagonal input normalized. One script (~250 lines) with:

```gdscript
enum State { NORMAL, ATTACKING, RELOADING, SHOVING, HURT, DEAD }
```

#### Player state machine

**Core rule: damage doesn't depend on state.** `HealthComponent.take_damage()` is called by zombie hitboxes directly and works in **every state except DEAD**. No state (SHOVING included) turns the hurtbox off or ignores damage, so there are **no invincibility frames**. This is covered by automated tests.

| State | Entered when | Lasts | Movement | Can run | Can fire/swing | Can reload | Can shove | Can switch weapon | Can interact |
|-------|--------------|-------|----------|---------|----------------|-----------|-----------|-------------------|--------------|
| NORMAL | default | — | 100% (aim-steady 50/80) | yes (stamina ≥ 10 to start) | → ATTACKING | → RELOADING | → SHOVING | yes | yes |
| ATTACKING | attack pressed, weapon ready (cooldown over, mag > 0 or melee) | firearm: 1 shot recovery (1 / fire_rate); melee: swing time | 70% (gun) / 50% (melee) | no | no (committed) | no | no | no | no |
| RELOADING | R pressed, or fire pressed with empty mag and reserve > 0 | weapon `reload_time` | 60% | no | no | — | **yes (cancels reload)** | **yes (cancels reload)** | no |
| SHOVING | Space, shove cooldown ready, stamina ≥ 15 | 0.25 s | 40% | no | no | no | no | no | no |
| HURT | a **heavy** hit only (single hit ≥ 25 damage, e.g. a future Brute). Walker bites (12) do **not** cause HURT | 0.3 s | 30% | no | no | no | no | no | no |
| DEAD | health reaches 0 (from any state; highest priority) | until respawn | 0 | — | — | — | — | — | — |

**Transitions**

```
NORMAL ──attack──► ATTACKING ──recovery done──► NORMAL
NORMAL ──reload──► RELOADING ──reload_time done (ammo moved atomically)──► NORMAL
                   RELOADING ──shove / weapon switch──► SHOVING / NORMAL   (reload cancelled; ammo unchanged)
NORMAL ──shove──► SHOVING ──0.25 s──► NORMAL
any except DEAD ──heavy hit──► HURT ──0.3 s──► NORMAL   (cancels attack/reload/shove; cancelled reload moves no ammo)
any ──health = 0──► DEAD ──respawn──► NORMAL (75 HP, at the safehouse bed)
```

- Light hits (Walker bites) apply damage plus feedback (flash, shake, sound) **without** changing state. A crowd can't stun-lock the player, and nothing grants immunity.
- **Reload is atomic.** Rounds move from reserve to magazine only at the moment the reload completes. Cancelling at any point moves nothing, so ammo can't be duplicated or lost.
- Stamina regeneration delay (1 s) restarts after running **or** shoving (see GDD §5).
- Only NORMAL allows running. Releasing or blocking run never changes state.

### 4.4 Weapons
`WeaponHolder` owns up to three slots of `WeaponData`, plus current magazine counts. Firing a hitscan weapon:
1. Check cooldown and magazine > 0 (otherwise play the empty click and auto-reload hint).
2. For each pellet: random angle within the spread, `PhysicsRayQueryParameters2D` ray to `range_px`.
3. First hit with a `Hurtbox` takes damage. Spawn a pooled tracer and impact effect.
4. `NoiseSystem.emit_noise(global_position, data.noise_radius, self)`.
Reload pulls `min(needed, reserve)` from the inventory. The HUD reads both numbers through signals.

**Ammo ownership (no duplication on weapon switch):** each weapon slot stores its own `rounds_in_mag`. Reserve ammo exists **only** in the inventory as an item stack (e.g. `ammo_pistol`). Switching weapons never moves ammo between the magazine and reserve. It only changes which slot is active, and it cancels an in-progress reload (which moves nothing). Two weapons sharing an ammo type draw from the same reserve stack. Automated test invariant: *rounds in all magazines + reserve in inventory + rounds fired = constant*, across any sequence of fire / reload / switch / cancel.

### 4.5 Zombie AI (performance-aware)
One `zombie.tscn` with `@export var data: ZombieData` (Walker/Runner/Brute differ only in data plus sprites).
- **State machine:** a single `match state:` block with enter/exit functions. For a beginner it's easier to read than a node-per-state framework, and it's enough for 8 states.
- **Think tick:** perception and decisions run on a `Timer` every **0.2 s**, with a random start offset so 40 zombies don't all think on the same frame. Only movement runs every physics frame.
- **Sight check:** a cheap distance check first, then the view-cone angle, *then* one raycast (most expensive, done last and only if needed).
- **Hearing:** `NoiseSystem` loops over the `"noise_listeners"` group, compares squared distance (no square root), and calls `hear_noise(pos, strength)`. One raycast per noise checks walls: a wall in the way halves the radius.
- **Pathfinding:** `NavigationAgent2D` on a navigation mesh. `NavigationBaker` (a NavigationRegion2D script) bakes it **at level load** (about 2 ms) from the collision of nodes in the `nav_source` group (wall and prop tile layers), with a 6 px agent radius; `rebake()` will be called when doors change (Phase 4). The navigation server syncs in the background (~0.2 s); until then zombies walk straight. Chasing zombies go straight at a visible player and only follow the path when they can't see them. Paths are recalculated only when the goal moved more than 16 px, at most every 0.25 s.
- **Sleeping:** calm (IDLE/WANDER) zombies farther than 700 px from the player go dormant: they think once per second and don't wander. Any noise or hit wakes them.
- **Group alert:** spotting the player emits a 140 px groan noise. Zombies that *hear* it investigate (they never groan themselves), so there's no runaway chain reaction.
- **Corpses:** collision removed; sprite stays up to a cap of 30 corpses, oldest fade out.

### 4.6 Noise & Light
- `NoiseSystem.emit_noise()` also emits `NoiseSystem.noise_emitted(position, radius, source)` so the HUD noise meter and the world "ring" effect can show it. *(Implemented Phase 6 on the NoiseSystem autoload itself; there is no separate EventBus.)* Rings: `scripts/world/noise_rings.gd`, created by `game.gd` under World; only the player's own noises ≥ 55 px, drawn unshaded. Running: 120 px every 0.4 s (`PlayerStats.run_noise_*`); walking is silent.
- **Localized interior darkness (corrected; CanvasModulate is NOT used for interiors).**
  `CanvasModulate` tints the *entire* canvas, so in one continuous scene it would darken the street too. Instead, each dark interior is a `DarkZone` scene with two separate parts:
  1. **Visual darkness:** a `PointLight2D` with `blend_mode = Subtract`, shadows off, whose texture is a soft-edged mask shaped like the interior floor. It subtracts ~88% of the brightness only inside that shape. Outside the shape the street is untouched. Soft mask edges give a natural gradient at doorways and windows. Irregular rooms use a baked mask PNG made from the room polygon, or a few rectangle masks.
  2. **Gameplay darkness:** an `Area2D` covering the same floor, which tells AI and HUD "the player is in darkness". Gameplay never samples pixels.
  - **Light masks:** the darkness light's `range_item_cull_mask` = layer 2 ("interior"). Floors, interior props, player, zombies and pickups include layer 2. **Roof tiles and the building's outer walls exclude it**, so roofs seen from the street aren't darkened.
  - **Flashlight:** a `PointLight2D` (Add mode) with a cone texture and shadows against `LightOccluder2D` walls and shelves. It adds light back on top of the subtraction. Battery drains in `GameState`. *(Implemented Phase 6: `Player/Flashlight`, texture `assets/sprites/flashlight_cone.png` ×1.2 ≈ 154 px beam, `shadow_item_cull_mask = 1` to match the tile/door occluders. `GameState.flashlight_charge` seconds, 180 per battery (`PlayerStats.flashlight_battery_seconds`); spare `battery` items are swapped in automatically. A new run starts with a full battery in the light.)*
  - **Readability:** zombie eyes (and later a faint rim) are a small child sprite with `CanvasItemMaterial.light_mode = Unshaded`, always visible even in full darkness. A very faint 20 px "eye adaptation" light around the player keeps the player's own silhouette readable.
  - **Nothing toggles on entry.** The darkness is always there in its area, so walking through a door never flips the whole screen.
  - **Cost:** one extra light per dark interior. Godot culls lights whose area is off-screen. The light budget (≤ 8 visible) and per-item light limits of the Compatibility renderer are re-checked in browser tests.
  - **Proof-of-concept render test (2026-11-08)** `[LINUX-AUTO]`, Godot 4.7.2 Compatibility renderer on Mesa llvmpipe (software OpenGL), one continuous scene with an outdoor street and a warehouse room. Pixel brightness (0–1): outdoor street **0.459** · street just outside the doorway **0.459** · dark interior floor **0.053** · flashlight-lit floor **0.395** · behind a shelf in the flashlight's path **0.053** (shadow works) · zombie eyes in the dark **0.826**. 6/6 checks passed. Screenshot: `documentation/research/lighting_spike.png`. *This proves the approach works in the engine. It does **not** prove how it looks on your Windows GPU or in a browser: those are `[WIN-PLAY]`/`[VISUAL]` and `[WEB-EXPORT]` checks, starting with the Phase 1 test yard.*
- Zombies ask a simple question: "is the player in darkness, and is their flashlight on?" Sight range is multiplied accordingly. There's no per-pixel light sampling, which would be too expensive. *(Implemented Phase 6: `Zombie.sight_multiplier_for()`, values `ZombieData.dark_sight_multiplier` 0.5 and `flashlight_sight_multiplier` 1.5.)*

### 4.7 Inventory
Slot-based list: `slots: Array[Dictionary]`, each `{id: StringName, qty: int}`, capacity 12 slots; `ItemData.max_stack` limits each slot. *(Implemented Phase 5: `scripts/inventory/inventory.gd`; API `count`, `add_item`, `remove_item`, `space_for`, `take_all`, signals `item_changed`, `contents_changed`.)*
`add_item(id, qty) -> int` returns **how many didn't fit**, so callers can leave the rest in the container. That's how "inventory full" is communicated without losing items. Same class used for the safehouse stash with unlimited capacity.

### 4.8 Loot (no-duplication guarantee)
*Implemented Phase 5:* `GameState` autoload (`scripts/autoload/game_state.gd`) holds `world_seed`, `containers` (id → rolled contents), `piles`, `stats`. RNG seed = hash(world_seed + container_id). Searching is a **timer on the player, not a player state** (`Player.start_search`, cancelled by moving, attacking, reloading, shoving, switching weapons or damage), so the Phase 2 state machine is unchanged. Guarantees come from `QuestGuarantees` (`data/objectives/quest_guarantees.tres`) plus each container's own `guaranteed_items`.
- Every `LootContainer` has an exported, unique `container_id` (validated by a test that scans the map for duplicates).
- First open: roll the `LootTable` with a seeded RNG, then store the result in `GameState.containers[container_id]`.
- Later opens read from `GameState`, never re-roll. Taking items removes them from that stored list.
- Saved as part of `GameState`, so it survives Continue.

### 4.8b Quest progression guarantees
Random loot can never block the main objective chain. Quest-critical items don't depend on random rolls:
- `LootContainer` has `@export var guaranteed_items: Array[ItemAmount]`. These are **always** added on the first open, *in addition to* the random loot table roll. Random rolls can't remove them.
- **Designated containers** (fixed `container_id`s, named in `data/objectives/quest_guarantees.tres`):

| Objective | Guarantee | Where |
|-----------|-----------|-------|
| 1. Stock up (5 food + 3 water) | ≥ **7 food** + ≥ **5 water** guaranteed in total (≥ 140% of need) | Grocery shelves `grocery_shelf_01..04` + residential kitchens `house_a_kitchen`, `house_b_kitchen` |
| 2. First aid (2 medical items) | ≥ **4 medical items** guaranteed (2 bandages + 1 medkit + 1 bandage) | `pharmacy_counter_01`, `pharmacy_cabinet_01`, `pharmacy_cabinet_02` |
| 3. Cut the lock | **Bolt cutters** ×1 | `vehicle_trunk_pickup_01` (pickup truck on the main street, *outside* the locked warehouse gate) |
| 4. Signal parts | **Radio component** ×1 | `warehouse_office_locker` (warehouse back office) |

- **Quest items can't be lost:** quest-category items can't be dropped or used up, and they go into the death backpack like other items. If a save is somehow missing a required quest item (not in inventory, stash, any backpack or its container) while its objective is incomplete, `ObjectiveTracker.validate_on_load()` respawns it in its designated container and logs a warning.
- **Ordinary resources** (extra food, water, ammo, scrap, batteries) still use random loot tables.
- **Automated tests** `[LINUX-AUTO]` (full list in the QA checklist):
  - each designated container exists exactly once in `ashford_lane.tscn`
  - 1,000 random seeds: guaranteed items are always present
  - guaranteed totals ≥ objective requirements
  - a navigation path exists from the safehouse door to each designated container, with all gates closed (bolt cutters reachable *without* the warehouse) and with the warehouse gate open (radio component)
  - quest items can't be dropped
  - death → backpack → recovery returns quest items intact
  - `validate_on_load` respawns a missing quest item

### 4.8c UI & settings (implemented Phase 8)
Phase 11: **Flashlight shadows** setting (`display/flashlight_shadows` in settings.cfg, default on). Off = `Flashlight.shadow_enabled = false` (cheaper; beam shines through walls). Visual only: zombie sight uses raycasts and is unaffected. The HUD FPS counter adds `MEM n MB` when the engine reports static memory (editor/debug runs).
- Start scene: `scenes/ui/main_menu.tscn`. New game → `GameState.new_game()` → `game.tscn`. Continue is disabled until saving exists (Phase 10).
- Look: one project theme (`assets/ui/theme.tres`, built by the generator) with an original 5×7 image font (`assets/fonts/last_signal_pixel.png`, size 10 = 1:1, 20 = 2× for titles via the `TitleLabel` type variation).
- `Settings` autoload: master/effects volume (audio buses Master + SFX, `default_bus_layout.tres`; AudioManager plays on SFX), fullscreen, V-Sync, FPS counter, key rebinding. Saved in `user://settings.cfg` (ConfigFile; only changed bindings are stored). Rebinding a key that another action uses swaps the two. The test runner resets bindings to the defaults in memory.
- Pause: `PauseMenu` sets `get_tree().paused`; it and `SettingsMenu` use `PROCESS_MODE_ALWAYS`, everything else stops. Gameplay timers are created with `process_always = false` so they pause too.

### 4.8d Art, animation, audio (implemented Phase 9)
- All art and sound is original, generated by the scripts in `tools/asset_generators/` (Python; not part of builds).
- Character sheets: 16×24 frames, one row per direction (down, left, right, up), animations side by side (layout lists `PLAYER_ANIMS` / `WALKER_ANIMS` in the generator and the builder). `Player.animation_for()` and the Walker's `_update_visuals()` pick the animation from the state; animations are visual only, the verified state machines don't read them.
- FX: `Fx.burst()` (CPUParticles2D, works in Compatibility/WebGL): blood on hits, dust/sparks where bullets hit walls; muzzle-flash sprite (unshaded) next to the muzzle light.
- `Soundscape` autoload: ambience (SFX bus) + music (Music bus) per mood (menu / outside / safehouse, chosen by whether the player is inside the safehouse), 2.5 s crossfades, keeps playing while paused; occasional distant groans from a living zombie 250–650 px away. Footsteps come from animation frames (sound only; zombie noise rules are unchanged).
- Cosmetic randomness (footsteps, pitch variation, groans, muzzle-flash frame) uses its own `RandomNumberGenerator`, never the global one, so gameplay randomness (and seeded tests) is unaffected.

### 4.9 Objectives
*Implemented Phase 7:* `ObjectiveData` types are `DELIVER_TO_STASH`, `LOOT_FROM` (items taken from containers whose id starts with a prefix, e.g. `pharmacy_`), `UNLOCK` (`GameState.unlocks`) and `HAVE_ITEM` (bag + stash). Order comes from `data/objectives/objective_chain.tres`. `ObjectiveTracker` (`scripts/main/objective_tracker.gd`, node `Objectives` in game.tscn) re-evaluates the current objective whenever the bag, the stash, the unlocks or the loot log change (signals on `GameState` and `Inventory`; there is no separate EventBus). Each objective is a condition on saved state, so progress made early still counts and completion happens exactly once. Delivered items are removed from the stash on completion. `validate_quest_items()` implements the §4.8b safety net (runs at start; Phase 10 calls it after loading). The warehouse gate uses `Door.unlock_item` (bolt cutters, used up) + `unlock_id` (recorded in `GameState.unlocks`). Safehouse furniture: `scenes/safehouse/safehouse_station.tscn` (kind STASH / BED / RADIO / BOARD), handled in `game.gd`.
`ObjectiveData` resource: `id`, `title`, `description`, `type` (`deliver_item`, `collect_item`, `reach_area`, `interact`), `target_id`, `amount`, `next_objective`. An `ObjectiveTracker` node listens to `EventBus` signals and updates progress automatically. No objective-specific code.

### 4.10 Saving
- File: `user://save_v1.json` (Windows: `%APPDATA%\Godot\app_userdata\LAST SIGNAL\`; web: browser IndexedDB, which Godot handles).
- Contents: `{ "version": 1, "player": {...}, "stash": [...], "containers": {...}, "unlocks": [...], "objectives": {...}, "stats": {...} }`
- Written to a temp file first, then renamed, so a crash mid-save can't corrupt it. On load: version check, migrate if older, fall back to New Game with a friendly message if the file is broken.
- Save points: sleeping in the safehouse bed and returning to the safehouse (autosave). No saving mid-expedition. That keeps the risk real and the save data simple.
- *Implemented Phase 10:* `SaveSystem` autoload (`scripts/autoload/save_system.gd`). Document: `{"version": 1, "saved_at", "reason", "player": {x, y, dead, health, inventory slots, rounds_in_mag, weapon}, "world": GameState.to_dict(), "game": {elapsed, dead_zombies, doors_open}}`. Save points: new game, entering the safehouse, bed, quitting to the menu from the safehouse, death. Desktop writes `.tmp` → verifies → old save to `.bak` → swap → remove `.bak` (reading falls back to `.bak`). Browser: one direct write (user:// is in memory there; Godot copies it to IndexedDB a moment after the file closes). Broken files are renamed `.broken`, never deleted. `migrate()` upgrades version 0 → 1; newer versions are refused. Loading: the menu calls `SaveSystem.load_game()` (restores GameState before the game scene is created, so doors and containers come up in the saved state), then `game.gd._restore_from_save()` applies the player, dead zombies and open doors and runs `validate_quest_items()`. Living zombies return to their start positions (saves only happen at the safehouse). Tests/tools set `SaveSystem.path` to their own file.

### 4.10b Death & recoverable backpack
On `HealthComponent.died` (player):
1. `Inventory.take_all()` returns every carried stack (implemented Phase 5 in `Player._drop_death_backpack()`). Equipped weapons, with their loaded magazines, stay on the player.
2. If the list isn't empty: `GameState.create_pile(position, items, backpack=true)` (stored in `GameState.piles` + `GameState.containers`). The position is snapped with `NavigationServer2D.map_get_closest_point()` so it's never inside a wall.
3. `SaveSystem.save()` runs immediately (anti-exploit), then the death screen shows.
4. On respawn or world load, `game.gd` spawns one pile node (a `LootContainer` with `is_pile = true`, backpack look) per `GameState.piles` entry. Taking the last item removes the entry and the node. *(Phase 5 note: there is no separate `death_backpack.tscn`; piles reuse `loot_container.tscn`. Step 3, the autosave, arrives with the save system in Phase 10.)*
Spent ammo and consumables were already removed from the inventory when used, so nothing has to be "un-restored".

### 4.10c Quick shove
`Player` → on `shove` action: check cooldown and stamina ≥ 15 → spend stamina → play the animation → query a cone (an `Area2D` with a `CollisionPolygon2D` wedge, enabled for one physics frame) → for each `Hurtbox` owned by a zombie: `zombie.apply_shove(direction, force * (1 - shove_resistance))`. The zombie enters `STUNNED` for the stagger time and cancels any attack wind-up. Player `State.SHOVING` slows movement but **doesn't** change hurtbox behaviour, so there's no invincibility.

### 4.10d World objects (Phase 4)
- **Interactable** (`scripts/components/interactable.gd`, Area2D on physics layer 5): `prompt` text or a live `prompt_provider`; `interacted(by)` signal. The player's **Interactor** (Area2D, 20 px) picks the closest interactable whose direction is within ~78° of the aim; HUD shows `[E] …`.
- **Door** (`scenes/world/door.tscn`, StaticBody2D on layer 1): width in tiles, vertical/horizontal, gate look, `locked`, `blocks_navigation`. Closed = collision + light occluder; open = disabled. `toggle()` refuses when locked or when a body stands in the doorway. Doors are **not** in the navigation mesh (zombies path through doorways and bang on closed doors). Locked gates with `blocks_navigation` **are**, until `unlock()` triggers `NavigationBaker.rebake()`.
- **Roof** (`scenes/world/roof.tscn`): covers a building's interior (z_index 20, light mask 1); an Area2D fades it out when the player is inside and posts the location name to the HUD.
- **LootContainer** (`scenes/world/loot_container.tscn`): `container_id` (unique, used by saves and quest guarantees), `container_type` (loot table in Phase 5), look. Group `loot_containers`.
- **Vehicle** (`scenes/world/vehicle.tscn`): car/pickup/bus; StaticBody2D in the `nav_source` group.
- **Group registration timing:** `nav_source` members join in `_enter_tree()`. `NavigationBaker` bakes deferred (after the whole level's `_ready`), so everything is included.

### 4.10e Night siege (Redesign Slice 1)
- `SiegeData` (`data/siege/siege_data.tres`): all cycle, horde, Heat, barricade and look numbers.
- `DayCycle` (`scripts/main/day_cycle.gd`, created by game.gd at runtime): advances `GameState.phase` / `phase_time` (DAY → DUSK → NIGHT → dawn), tints the world with a `CanvasModulate` (world canvas only; HUD unaffected; interior darkness still uses the local Subtract lights), turns on a warm `PointLight2D` lamp in the safehouse, marks the player "in darkness" outdoors at night, spawns the horde at the `HordeSpawns` markers (never within 360 px of the player) over the first 60 % of the night, removes surviving horde Walkers at dawn, restocks 5 emptied non-quest containers (`GameState.restock`: new roll key `seed:id:restockN`), emits `dawn(summary)`. A save from dusk/night restarts at the start of dusk.
- Heat: `NoiseSystem.noise_emitted` → `GameState.add_heat(radius / 480)` for non-zombie noises ≥ 200 px during day/dusk.
- `Barricade` (`scenes/world/barricade.tscn`): 1-tile window in a wall; physics **layer 6 "barricades"** (player mask 1|4|32, zombie mask 1|2|4|32), so bullets, sight and light pass through. Health pool in `GameState.barricades`. Player: E → `Player.start_work()` (generic timed job: moving, attacking or getting hurt cancels) → plank. Zombies: `_check_blocked_by_barricade()` hits it every 1.5 s via slide collisions.
- Navigation: each window carries a nav-only blocker (physics **layer 7**, parsed by the baker, collides with nothing) and a bidirectional `NavigationLink2D` on **navigation layer 2**. Zombie agents use layers 1|2 (they path through windows and hit the boards); default path queries use layer 1 (go round to the door). Zombies crossing a link head straight for the exit point (no re-pathing in the gap).
- Horde Walkers: `Zombie.siege_goal` (a point just inside a window). When calm they march there (INVESTIGATE with a 120 s patience) and never go dormant; noises and the player still distract them.
- `scripts/ui/dawn_panel.gd`: morning summary (pauses the game), "RESCUED" variant after night 10 with the radio repaired, then "Keep surviving".

### 4.10f Fun pass
- `Population` (`scripts/main/population.gd`, runtime node): by day keeps `10 + nights` (max 18) zombies within 520 px of the player; spawns one per second out of view (380–560 px, on the navigation mesh, never in the safehouse), 20 % Lurchers, 50 % "heard something" (walk towards the player); removes far, calm spawns and far corpses (950 px). Off at dusk/night, in tests and tools (`GameState.street_spawns_disabled`).
- Lurcher = `data/zombies/lurcher.tres` (same scene, new ZombieData with `tint` and `score`).
- `Juice` (`scripts/world/juice.gd`): hit-stop via `Engine.time_scale` (skipped headless, so tests and bots are unaffected), world popups, kill bursts.
- `ScoreKeeper` (`scripts/main/score_keeper.gd`): every zombie death reaches the `score_listeners` group (game.gd counts kills there too); streak window 4 s, ×5 max; +2 per looted item (not your own piles), +100 objective, +50 × night; blood splats (max 80). Records `best_score` / `best_nights` in settings.cfg (`[records]`), never from tests (`GameState.records_disabled`). `GameState.score` is saved.
- `GoalFinder` + `scripts/ui/goal_marker.gd`: HUD arrow to the next useful place, recomputed 4× per second.
- Horde corpses are cleared at dawn (no pile-up over many nights).

### 4.10g Screen fitting (2026-11-09)
`project.godot`: stretch mode `viewport`, aspect `expand`, scale mode `fractional`; `Settings.fit_screen()` (on start and on every window resize) sets `root.content_scale_size = Settings.view_for(window)`: zoom = floor(min(w/640, h/360)), view = ceil(window/zoom) (so the zoom is a whole number and the window is filled), unless that is larger than 860×484, then 640×360 smooth-scaled. Desktop default fullscreen (settings `layout_version` 1 migrates old files once). Population / DayCycle spawn distances grow with the visible area (half diagonal + 30 px). Mobile portrait is not a target yet (§4.11).

### 4.10h Slice 2: perks, Your Echo, new weapons, intro
- **Perks**: `PerkData` / `PerkPool` (`data/perks/perk_pool.tres`, 13 perks), `Perks` static helpers (no static vars). `GameState.perks` (id → stacks, saved) + `perks_changed`. Player keeps `base_stats` and `stats = Perks.apply_to_stats(base_stats)` (noise, stamina, speed, health, battery, shove); bag slots = base + Deep Pockets. Weapon damage/reload multipliers in WeaponHolder; search time in LootContainer; plank health in `Barricade.plank_health()`; Bloodlust in ScoreKeeper. Dawn panel shows 3 cards (`Perks.offer(3)`), Continue only after a pick (or when everything is maxed); tests/bots use `pick_first_and_close()`.
- **Your Echo**: `EchoManager` (runtime node). On `Player.backpack_dropped` (non-empty) it waits 1.5 s, sets `GameState.piles[id].echo = true` (the pile node is removed: `_sync_piles` skips echo piles) and spawns a Walker scene with `data/zombies/echo.tres` and the player's SpriteFrames (+ `attack_*` copied from `melee_*`), group `echoes`, tag "YOUR ECHO". Every 0.5 s the pile position follows the Echo (HUD arrow, saves). On its death: pile position = snapped Echo position, echo = false → backpack appears. Loaded games respawn Echoes from the flag.
- **Weapons**: `ItemData.weapon` (shotgun, fire_axe items). Inventory accepts weapon items without bag space; Player moves them into `WeaponHolder.add_weapon()` (next slot, loaded) and switches to them. Saved as `player.weapons` ids. Weapon caches = `LootContainer.guaranteed_items` on `house_a_bedroom` and `house_c_toolbox` (never restocked). Input `weapon_4`. Shotgun shells also in vehicle trunks.
- **Intro**: `scripts/ui/intro_panel.gd`, created by game.gd for fresh games unless `GameState.intro_disabled` (tests/tools).

### 4.10i Batch 1: Brute, Screamer, night events, supply drops
- `ZombieData` gained `body_scale`, `barricade_damage_mult`, `door_hits_to_break`, `scream_radius` (Brute: `data/zombies/brute.tres`, Screamer: `screamer.tres`, same Walker scene). `Door.smash_open()` (unlocked doors only). `Zombie.scream()` on spotting the player (10 s cooldown; zombie-sourced noise, so no Heat).
- `NightEvents` (`scripts/data/night_events.gd`): ids, titles, weights, horde multiplier, night tint; `pick(night, last, world_seed)` is seeded. `GameState.night_event` (saved). DayCycle picks at dusk, announces via `hud.show_banner`, applies the horde mix in `_spawn_horde_walker`, the multiplier in `horde_estimate`, tint and Blackout lamp in `_apply_look`. Blood Moon doubles night kill score (ScoreKeeper).
- `SupplyDrops` (`scripts/main/supply_drops.gd`, runtime): on dawn (day ≥ 2) a `supply_crate` container (`data/loot_tables/supply_crate.tres`) with a pulsing red PointLight2D flare and smoke at a seeded site from `SITES`; guards join the `population` group. `GameState.supply_drop` (saved, same-day restore). HUD second arrow = `goal_marker.gd` with a `provider` callable.

### 4.10j Batch 2: survivors, characters, daily challenge, playtest log
- `Characters` (`scripts/data/characters.gd`, const table): unlock rules read the lifetime records in `Settings` (`best_score`, `best_nights`, `lifetime_kills`, `lifetime_rescued`); `Characters.apply(id, base)` runs first inside `Perks.apply_to_stats`, then `DailyChallenge.apply_to_stats`, then the perks. `GameState.character` (saved; Rook whenever `records_disabled`). Starting gear: `game._give_start_gear()` on a fresh start. Look: `player.sprite.self_modulate` tint (modulate stays free for hit flashes).
- `DailyChallenge` (`scripts/data/daily_challenge.gd`): `seed_for(date)`, `modifier_for(date)`, effect helpers (horde/score/day length/lamp/forced Brutes/stats), `begin()` sets `GameState.mode = daily` and `SaveSystem.path = user://save_daily.json` (the menu resets the path to the main save). One life: `game._on_player_died` → `GameOver.show_daily` (Try again restarts the same date). `Settings.daily_best` (date → score, 30 days).
- `Survivors` (`scripts/main/survivors.gd`, runtime node) + `SurvivorNPC` (`scripts/world/survivor_npc.gd`, Node2D, player SpriteFrames, Interactable, path-follow via `NavigationServer2D.map_get_path` layer 1, no physics body). `game._on_dawn` calls `survivors.on_dawn(summary)` before the dawn panel (losses from `summary.breaches`, counted by DayCycle from `Barricade.broken` at night; Doctor/Scavenger jobs; radio announcements). Mechanic on DUSK, Guard on NIGHT (`guard_shoot`, `Hurtbox.receive_hit`). `GameState.survivors` (saved). HUD third arrow (green) with `provider = survivors.target`.
- `SessionLog` (`scripts/main/session_log.gd`, group `session_log` + `score_listeners`): enabled by `Settings.playtest_mode` unless `records_disabled`; appends to `user://playtest_log.csv` and `user://playtest_summary.txt` (`csv_path`/`summary_path` overridable for tests). `RatingRow` (`scripts/ui/rating_row.gd`) on the death screen and the pause menu → `SessionLog.rate`.
- HUD banners queue (`_banner_queue`, max 4, duplicates dropped).

### 4.11 Input & mobile readiness
All gameplay reads **actions** (`Input.get_vector("move_left", ...)`), never raw keys. Aim is an abstract `aim_direction` the player script receives. Mouse sets it on desktop; Godot 4.7's built-in `VirtualJoystick` can set it on Android later without touching gameplay code.

## 5. Testing & validation strategy

Every test result in every report is labelled with **one of five categories**. A pass in one category is never reported as proof for another.

| Category | Label | What it proves | What it does NOT prove | Who runs it |
|----------|-------|----------------|------------------------|-------------|
| **Linux automated tests** | `[LINUX-AUTO]` | Scripts parse, project imports, scenes load, unit and simulation tests pass on Godot 4.7.2 (Linux headless, same version as your editor) | That it looks right, feels right, or runs on Windows | Claude, after every change |
| **Windows automated checks** | `[WIN-AUTO]` | `tools/validate.bat` runs your **Windows** Godot 4.7.2 headless: import, scene load and the same test suite, results in `logs/validate.log` | Gameplay feel, visuals, browser | You double-click; I read the log from your folder |
| **Windows gameplay tests** | `[WIN-PLAY]` | The game plays correctly on your PC (editor F5 or exported .exe), following the steps I give | Browser behaviour, code correctness beyond what you tried | You |
| **Browser export tests** | `[WEB-EXPORT]` | The HTML5 build exports, loads and runs in a browser | Desktop behaviour | Export: Claude (Linux headless). Load test: Claude in a headless browser if available; **final confirmation by you** in Chrome/Edge on Windows |
| **Manual visual verification** | `[VISUAL]` | Art, animation, readability, UI layout, feel | Code correctness | You (screenshots welcome) |

Only `[WIN-PLAY]` + `[VISUAL]` passes, confirmed by you, move a feature to **VERIFIED**.

**Linux automated layers:**
- Import / parse: `godot --headless --path . --import` (the output log is scanned; any `SCRIPT ERROR`, `Parse Error` or `ERROR:` line marks the run FAILED, because Godot doesn't always return a non-zero exit code)
- Scene load: a test that `load()`s and `instantiate()`s every `.tscn`
- Unit tests: inventory, loot no-dup, ammo math, backpack, save round-trip, objectives (`tests/run_tests.gd`, a tiny runner extending `SceneTree`, no plugin)
- Simulation tests: spawn player + zombie, step physics N frames, assert positions and states

**Browser export pipeline (from Phase 1):**
- Web export template 4.7.2 (official, free). **Thread support OFF** (single-threaded build), so it runs on itch.io and plain static hosting without special COOP/COEP server headers.
- `godot --headless --export-release "Web" export/web/index.html`, then served locally and loaded in a headless browser. The test looks for a "READY" line the game prints to the browser console.
- You then open the same build in Chrome/Edge on Windows (instructions given per phase).

**Phase 11 QA tools** (all under `tests/`, excluded from exports):
- `tests/scenarios/playthrough_bot.tscn`: a bot plays from a new game to the ending by **walking** the real map (movement input along navigation paths, collisions on, doors opened with E, real searches, stash and radio). Mode A, pass/fail: no Walkers, 5 world seeds. Mode B, report only: normal Walkers, can't die, fights with bat and shove; records bites and kills. Run by `validate.sh` / `validate.bat` every time.
- `tests/perf/soak_test.tscn`: 12 full sessions (menu, new game, shots, effects, death, respawn, save, Continue) and one 5-minute session; fails if objects, nodes or memory keep growing or orphan nodes remain. Run every time.
- `tests/perf/perf_benchmark.tscn` (`validate.bat perf`): FPS and frame times; `-- --quick` = V-Sync OFF rows only. Output file named after the graphics driver (`perf_benchmark_opengl3.txt`, `perf_benchmark_opengl3_angle_quick.txt`). Includes the "Flashlight shadows" OFF rows.
- `tests/perf/hitch_probe.tscn`: one-time stutters the first time the flashlight, a shot, an effect or a menu appears (each action twice).
- `tests/perf/render_breakdown.tscn` and `tests/perf/cpu_probe.tscn`: Claude's profiling helpers (render cost per scene part; game-logic cost by wall clock).

**Phase 11 measurements** `[LINUX-AUTO]`, 2-thread Xeon, software OpenGL (llvmpipe) — relative numbers only, not your PC:
- Game logic (physics + AI + scripts), wall clock, headless: **0.8 ms per frame with 40 Walkers** chasing in Ashford Lane, 1.9 ms with 80. Not a bottleneck, so the AI was not changed. (Note: the engine's `TIME_PHYSICS_PROCESS` monitor reads much higher than the wall clock in headless runs, so the benchmark's "phys+AI" column is only a rough guide.)
- Rendering is the cost. Switching parts of the real map off one at a time (warehouse view, software rendering): ground layer about 6.6 ms of 10, dark-zone lights about 3 ms, HUD about 2 ms, zombies, roofs, wall occluders and effects each under 0.5 ms. The flashlight adds about 6 ms with shadows and about 3 ms without them.
- No one-time stutters found on first flashlight, shot, blood, inventory or pause (all within normal frame-time noise in software rendering; to be confirmed on your GPU by `perf_hitches.txt`).
- Memory: 0 orphan nodes; objects and nodes return to exactly the same count after every full session (12 cycles); a 5-minute session keeps a flat node count.
- **30 FPS on your laptop:** not reproducible here (software rendering, no V-Sync). Candidates, in the order `validate.bat perf` checks them: V-Sync on a screen where frames take slightly longer than 16.7 ms (V-Sync OFF rows), the slow OpenGL driver of some laptop graphics chips (ANGLE / Direct3D 11 rows: if ANGLE is clearly faster, Phase 11b sets `rendering/gl_compatibility/driver.windows = "opengl3_angle"`), the game running on the integrated instead of the dedicated GPU, a 30 Hz screen mode, battery-saver power plan, or running from the editor (`perf_system.txt` records these).

## 6. Performance budget (target: your Ryzen 5 5600H / 8 GB, plus a mid-range browser)

- 60 FPS with 40 active zombies on screen-adjacent areas.
- ≤ 8 dynamic lights visible at once, shadows only on the flashlight plus key lights.
- RAM < 400 MB desktop. Web download < 40 MB compressed.
- No per-frame `get_tree().get_nodes_in_group()` calls in hot paths. Cache or use the tick.

## 7. Technical risks

| Risk | Impact | Mitigation |
|------|--------|-----------|
| **Art production**: Claude cannot hand-paint production-quality animated pixel art | High | Original programmatic placeholders until Phase 9, then a verified CC0/commercial asset pack (with your approval) or a commissioned artist. See asset strategy in the roadmap. |
| Web build: 2D lights and shadows cost more on WebGL | Medium | Light budget above. Test a web export at the end of Phase 6, not Phase 12. |
| Web saves (IndexedDB) can be cleared by the browser | Low-Med | Document it. Optional export/import save string later. |
| Web audio needs a user click before sound plays | Low | The main menu "click to start" naturally unlocks audio. |
| Navigation with doors that open/close | Medium | Doors are obstacles; zombies path *to* doors and bang on them (Brute breaks). Rebake avoided. |
| Many zombies plus raycasts | Low (measured Phase 11: 0.8 ms per frame for 40 Walkers) | Tick staggering, distance culling, dormant mode (4.5). Profiler pass in Phase 3 and Phase 11. |
| Scope creep | High | GDD §15 scope list. New ideas go to a "Later" list, not the current phase. |
| Git in the shared folder: my workspace can't delete files there by default, and Git needs that internally | Low | **Owner decision:** no broad delete permission. You run `git init` / `git commit` yourself on Windows using commands I provide; I never run destructive Git commands (reset, clean, checkout over files). |
| Linux tests passing ≠ Windows/browser working | Medium | Five labelled test categories (§5). Nothing is VERIFIED without your Windows + visual check. |
| Software-GL render tests differ from real GPUs | Low | Linux render tests only check relative brightness, never exact looks. Visual sign-off is always yours. |
