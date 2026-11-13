# LAST SIGNAL — Game Design Document

Version 0.4 (2026-11-08: **night siege redesign** approved by owner, see §0) · Engine: Godot 4.7.2 · Status: Phases 0–11 built; Slice 1 of the redesign in progress

All numbers in this document are **first-pass tuning values**. They live in data files (`data/*.tres`), so they can be changed without code changes during play-testing.

---

## 0. Redesign: "Every night, the radio calls. Every night, they come." (approved 2026-11-08)

The owner found the Phase 0–11 game not interesting enough: one short linear quest, one enemy type and no reason to come back. Approved direction: a **day/night siege loop** with four hooks. Everything in §1–15 still applies unless this section changes it.

**Core loop (one day):**
- **Day** (5 min): scavenge. Loud noises raise **Heat**. The HUD shows the clock, Heat and "tonight: ~N of them".
- **Dusk** (45 s): get home, nail planks over the safehouse windows (E, 1 scrap each, max 3).
- **Night** (2.5 min): the horde (base 4, +1.5 per night, +0.75 per Heat, capped at 40 Walkers awake) walks in from the map edges and attacks the three windows. The front door can't be broken; windows can. Outside it's dark (Walkers see you at half range; a lit flashlight gives you away).
- **Dawn**: the horde leaves, summary screen, the night counts, Heat resets, 5 emptied town containers get fresh loot (never quest containers), autosave.
- **Goal:** repair the radio (existing objective chain) **and** survive 10 nights → the convoy rescues you. Then "Keep surviving" (endless).

**Hooks (owner selected all four):**
1. **Your Echo** (Slice 2): when you die you rise as a zombie carrying your backpack and gun; kill your past self to get your gear back.
2. **The town listens / Heat** (Slice 1): every loud noise by day (≥ 200 px: gunshots, forcing locks) makes tonight's horde bigger.
3. **New zombie types** (Slice 3): Screamer (shriek wakes the block), Brute (breaks barricades and doors), Crawler (hides in dark rooms), Runner (night only).
4. **Survivors + throwables** (Slice 4/5): rescued survivors live in the safehouse with jobs (Doctor heals overnight, Mechanic strengthens boards, Kid finds loot) and can die in raids; bottles/alarm clocks/firecrackers as noise lures.

**Slices** (each one playable and play-tested before the next): 1 day/night + siege + barricades + Heat · 2 Echo + perk cards + morning score · 3 new zombie types · 4 survivors + radio missions · 5 throwables/crafting, game feel (hit-stop, combos), endless + daily seed. Publishing (old Phase 12) comes after.

**Fair design:** the pull comes from clear goals, risk/reward and growing stronger, never from manipulative tricks (no fake rewards, no login timers, no paid anything).

---

## 1. One-line pitch

A tense top-down 2D survival game where every gunshot is a decision: scavenge an infected neighbourhood, manage scarce ammo and light, and get back to your safehouse alive, one expedition at a time, until the emergency radio is repaired.

## 2. Player fantasy

> "I am a survivor trapped in an infected city. Every trip outside is dangerous. Ammunition is limited, noise brings more of them, and I have to make it back alive."

## 3. Design pillars

Every feature is checked against these. If a feature does not serve at least one, it is cut.

| # | Pillar | What it means in practice |
|---|--------|---------------------------|
| 1 | **Noise is a currency** | Every loud action buys something (a kill, a fast escape, an opened crate) and costs attention from the horde. |
| 2 | **Risk vs. return** | The deeper you go, the better the loot, and the more you lose if you die before getting home. |
| 3 | **Readable danger** | The player can always see and hear why something went wrong. Zombies telegraph attacks, noise shows a ring, darkness has clear edges. |
| 4 | **Small and polished** | One compact, handcrafted neighbourhood done well beats a big empty map. |

## 4. Core loop

```
 SAFEHOUSE ──► plan (check objective, pick loadout, heal)
     ▲                       │
     │                       ▼
  deposit loot         EXPEDITION: explore → loot → noise → zombies react
  progress objective         │       fight / sneak / flee
     │                       ▼
     └──────────── return alive  ──or──  die → backpack dropped, respawn at safehouse, go recover it
```

### Death rule — recoverable backpack (APPROVED by owner)

| On death… | What happens |
|-----------|--------------|
| Safehouse stash | **Always protected.** Never touched. |
| Permanent progression (completed objectives, unlocked areas, radio repair progress, safehouse upgrades) | **Kept.** |
| Equipped weapons (up to 3 weapon slots) | **Kept** by the player, with whatever rounds are currently loaded in their magazines. |
| Everything else carried (resources, reserve ammo, medical items, quest items picked up this expedition) | **Dropped into a backpack** at the death location. |
| Ammo fired, bandages/medicine used, batteries drained | **Not restored.** Spent is spent. |
| Containers already looted | Stay looted (no re-rolling). |

**Backpack rules**
- The backpack is a world object at the exact death position, snapped to the nearest walkable navigation point. This prevents it landing inside a wall.
- It stays **until the player recovers it**. It never expires and it's saved with the game.
- If the player dies again before recovering it, **a second backpack is created**. Every backpack stays until recovered. There is no hard limit, though in practice there will rarely be more than one or two.
- Recovery: walk up and press **E**, which opens a transfer screen (Take all / take individual items). Items that don't fit stay in the backpack.
- It's marked on the HUD with an edge-of-screen arrow and distance, so the player always knows where to go.
- Zombies are **not** removed when the player dies. The area around the backpack is usually still dangerous, and that's the point.
- Quest items (bolt cutters, radio component) go into the backpack like anything else, so an objective can never be soft-locked.
- **Anti-exploit:** the game autosaves immediately on death (backpack + respawn state). Quitting and reloading cannot undo a death.

**Respawn:** at the safehouse bed, with **75 HP** (tunable). Full heal requires sleeping or using medicine.

## 5. Player

| Stat | Prototype value | Notes |
|------|-----------------|-------|
| Health | 100 | No passive regen outside the safehouse |
| Walk speed | 80 px/s | Very quiet |
| Run speed | 140 px/s | Moderate noise, drains stamina |
| Stamina | 100 | Run drains 20/s (= 5 s of sprinting). Regenerates 15/s after 1 s without running or shoving. Can't start running below 10 |
| Acceleration | 900 px/s² | Reaches walk speed in ~0.09 s: responsive, not twitchy |
| Deceleration (friction) | 1200 px/s² | Stops in ~0.07 s, no sliding |
| Aim-steady walk speed | 50 px/s (right mouse held) | Also reduces gun spread by 50% |
| Speed while firing | 70% of current | |
| Damage taken | No invincibility frames | Several zombies biting together is meant to be deadly |
| Hurt feedback | 0.1 s red flash, 3 px camera shake, grunt sound, red screen-edge vignette below 30 HP | |
| Carry capacity | 12 inventory slots | Stackable items share a slot up to their stack limit |

Animations required (final art): idle, walk, run, melee, shoot, reload, hurt, death — 4 directions minimum (8 desirable), top-down 3/4 view.

### Controls (defaults, all remappable through Godot's Input Map)

| Action | Key | Input-map name |
|--------|-----|----------------|
| Move | W A S D | `move_up/down/left/right` |
| Aim | Mouse | — |
| Attack / fire | Left mouse | `attack` |
| Aim steady (reduces spread, slows walk) | Right mouse | `aim` |
| Reload | R | `reload` |
| Interact | E | `interact` |
| Run | Shift | `run` |
| Quick shove / melee | Space | `shove` |
| Flashlight on/off | F | `flashlight` |
| Weapon slots | 1 / 2 / 3, mouse wheel | `weapon_1..3`, `weapon_next/prev` |
| Inventory | Tab or I | `inventory` |
| Pause | Esc | `pause` |

### Quick shove — Space (APPROVED by owner)

A short, committed push that buys space without using ammo. It does **not** make the player invincible.

| Property | Initial value |
|----------|---------------|
| Shape | Cone in front of the player (toward the mouse aim), **120° wide, 36 px long** |
| Targets | **All** zombies inside the cone (it can push several) |
| Knockback | 220 px/s initial push, slowing to zero over 0.25 s (≈ 25 px of travel) |
| Stagger | Zombie can't attack for **0.6 s** after being shoved (attack wind-up is cancelled) |
| Damage | **2** (essentially none; it's for space, not kills) |
| Noise | 50 px radius (quiet) |
| Stamina cost | **15**. Can't shove below 15 stamina (the HUD stamina bar flashes) |
| Cooldown | **1.0 s** |
| Player during shove | 0.25 s animation. Movement slowed to 40%, **can still be hit and takes full damage**, can't fire or reload |
| Usable with | Any equipped weapon (pistol in hand included) |
| Feedback | Shove animation (arms forward) · whoosh sound on use · thud + zombie grunt on contact · tiny camera kick (2 px) · zombie flashes white |
| Per-zombie resistance | `shove_resistance` in zombie data: Walker 0.0 (full push), Runner 0.0, Brute 0.8 (barely moves, no stagger) |

### Starting loadout (new game)
Wooden bat (slot 1) · Pistol (slot 2) with **8 loaded + 16 reserve** rounds · **2 bandages**. Flashlight with 1 full battery inside (3 minutes of light; added in Phase 6). Spare batteries are found as loot.

## 6. Combat

### Melee
| Weapon | Damage | Cooldown | Range | Noise | Special |
|--------|--------|----------|-------|-------|---------|
| Wooden bat | 25 | 0.6 s | 28 px arc | Low (impact) | Knockback |
| Metal pipe | 35 | 0.8 s | 28 px arc | Low-moderate | Short stun chance |
| Knife | 18 | 0.35 s | 18 px | Very low | Silent, best for stealth |

Melee needs commitment: there's a wind-up, you can be hit during it, and a swing at a crowd only hits the front arc.

### Firearms (data-driven, added one at a time)
| Weapon | Dmg | Rate | Mag | Reload | Spread | Ammo | Noise radius |
|--------|-----|------|-----|--------|--------|------|--------------|
| Pistol | 34 | 3/s | 8 | 1.2 s | 4° | pistol | 480 px |
| Shotgun | 6 pellets × 14 | 1/s | 4 | 0.5 s per shell | 18° | shotgun | 640 px |
| Rifle | 70 | 1.2/s | 5 | 2.0 s | 1° | rifle | 720 px |

Firearms are hitscan (an instant ray) with a short tracer visual. That's cheaper and more reliable than physics bullets, and it reads well top-down. Ammunition is tracked as *magazine* + *reserve in inventory*. Reload moves rounds from inventory into the magazine. There is never infinite ammo.

## 7. Zombies

### States (shared by all types)
`IDLE → WANDER → INVESTIGATE (noise) → SEARCH (last seen spot) → CHASE → ATTACK`, plus `STUNNED` and `DEAD`.

- **Sight:** cone (~110°) + range; blocked by walls (raycast). Range is boosted when the player's flashlight is on, cut when the player is in darkness.
- **Hearing:** every noise event has a position and radius; walls between source and zombie reduce the effective radius.
- **Group alert:** a zombie entering CHASE groans (a small noise), which can pull nearby zombies into INVESTIGATE. Gunfire in a crowded street can cascade.
- **Telegraph:** zombies pause and lunge (0.4 s wind-up) before attacking, so good players can dodge.

| Type | HP | Speed | Damage | Notes | Phase |
|------|----|-------|--------|-------|-------|
| Walker | 60 | 45 px/s | 12 | The baseline; dangerous in groups | 1–3 |
| Runner | 35 | 120 px/s chase | 8 | Short sight range, aggressive, high-value areas | Post-MVP |
| Brute | 220 | 35 px/s | 30 | Breaks doors, staggers on shotgun hits | Post-MVP |

### Walker — full initial values
| Property | Value | Meaning |
|----------|-------|---------|
| Health | 60 | Bat: 3 hits · Pipe: 2 hits · Pistol: 2 shots |
| Wander speed | 25 px/s | Slow shuffle |
| Investigate speed | 35 px/s | |
| Chase speed | 45 px/s | Player walking (80) outpaces it; groups are the threat |
| Bite damage | 12 | Player (100 HP) survives 8 bites |
| Attack range | 18 px | Must be nearly touching |
| Attack wind-up (telegraph) | 0.4 s | Lean back + growl. Step away to make it miss |
| Attack cooldown | 1.2 s | Between bites |
| Sight range | 160 px (10 tiles) | ×0.5 when the player is in darkness with the light off · ×1.5 with the flashlight on in darkness |
| Sight cone | 110° | Can't see behind itself |
| Close-proximity sense | 24 px all around | Notices a player bumping into it from behind |
| Hearing | 1.0 × noise radius | |
| Search duration | 6 s | At the last known position before giving up |
| AI think interval | 0.2 s (staggered) | |
| Hit stun | 0.15 s per hit (pipe: 35% chance of 0.8 s stun) | |

**Difficulty note (owner decision):** a lone Walker (45 px/s) is slower than a walking player (80 px/s) **on purpose**. The danger comes from groups, tight spaces, darkness and being caught while searching containers. These values stay as they are until real gameplay tests show otherwise (test plan: DEVELOPMENT_ROADMAP → "Walker difficulty testing"). Difficulty is never raised without test data.

## 8. Noise & Light system (signature mechanic)

| Action | Noise radius (px) | Feedback |
|--------|-------------------|----------|
| Walk | 0–40 | none |
| Run | 120 | faint ring |
| Open drawer/shelf | 60 | faint ring |
| Force a locked crate / smash glass | 260 | ring + sound |
| Melee impact | 90 | — |
| Pistol shot | 480 | strong ring |
| Shotgun shot | 640 | strong ring |
| Car alarm / noise-maker | 900 | big pulsing ring |

- A small **noise meter** on the HUD shows how loud you currently are. Gunshot rings are briefly shown in the world, so cause and effect are learnable.
- **Darkness:** some interiors (warehouse, back rooms) are dark. The darkness is **local to each interior**: the street outside stays fully lit, and walking through a doorway never darkens the whole screen. (Technique: TECHNICAL_ARCHITECTURE §4.6; proven in an engine render test.) The flashlight (cone light, blocked by walls and shelves) costs battery. 1 battery ≈ 3 minutes.
- **Light gives you away:** inside dark areas, a lit flashlight extends zombie sight range toward you by 50%.
- **Readability rule:** zombies always have a faint rim/eye glow so they're never invisible in the dark.

Distraction tools (thrown bottle, noise-maker) are planned post-MVP. The noise system is built so they're just "emit noise at position X".

## 9. World — "Ashford Lane" (working name, original fictional neighbourhood)

### 9.1 How the map works (structure)

- **One continuous scene, no loading screens.** The whole neighbourhood is a single Godot scene (`ashford_lane.tscn`). Walking out of the safehouse and into the grocery store is seamless. That keeps tension high and makes zombies able to follow you anywhere.
- **Buildings have real interiors in the same scene.** Each building has a *roof layer*. When you walk through a door, that building's roof fades out (an `Area2D` trigger) and you see the interior. Outside, roofs hide interiors, so you can't see what's waiting inside.
- **Layers (TileMapLayer nodes):** `Ground` (roads, floors) → `Walls` (collision + light occluders) → `Props` (shelves, cars; collision) → `Roofs` (fade when inside). Doors, containers and the backpack are separate scenes placed on top.
- **Navigation:** one navigation mesh baked from the walkable ground. Zombies path through streets and open doorways. Closed doors block them (in the MVP, Walkers bang on closed doors, which makes noise. Brutes break them later).
- **Gates:** areas not yet unlocked are blocked by in-world objects (a chained warehouse gate, a wrecked bus), never invisible walls.

### 9.2 Size

**160 × 86 tiles** (2560 × 1376 px) ≈ 4 × 3.8 screens at 640×360. Walking across takes ~32 s and running ~18 s, before detours and zombies.
*(Phase 4: reduced from 100 to 86 tiles tall. The southern 14 rows were empty grass with no gameplay purpose.)*
*(Correction: v0.1 said 120 × 80 tiles and "~40 s", which didn't match. These numbers are the corrected version.)*

### 9.3 Layout (MVP areas in bold; tile coordinates approximate)

```
x→ 0         40          80          120         160
y  ┌──────────────────────────────────────────────────┐
0  │  WAREHOUSE (dark)        │   Police checkpoint*  │   North block (post-MVP gate:
   │  [chained gate]          │                       │    bolt cutters)
22 │══════════════ MAIN STREET (east–west) ═══════════│
   │   wrecked cars · alarm car · bus blocks east end │
30 │  ┌PHARMACY┐   ║   ┌──GROCERY STORE──┐  ║ house C│   Middle block
   │  │ front  │   ║   │ front doors face │  ║        │
   │  │ door ↓ │ CROSS │ residential st.  │ CROSS     │
   │  └─back──┘ STREET└──back door → alley┘ STREET   │
55 │══════════════ RESIDENTIAL STREET (east–west) ════│
   │  house A        ┌─SAFEHOUSE─┐        house B     │   South block
   │                 │ front door↑│                    │
   │                 │ (fenced yard)                   │
100└──────────────────────────────────────────────────┘
 * post-MVP
```

### 9.4 Routes between the MVP locations

| Route | Path | Distance | Walk / run | Danger |
|-------|------|----------|-----------|--------|
| Safehouse → **Grocery store** | Out the front door, through the fenced yard gate, north across the residential street straight to the grocery's front doors | ≈ 35 tiles | ~7 s / ~4 s | Low: 2–3 Walkers drift on the residential street |
| Safehouse → **Pharmacy** | Residential street west, then the west cross street north to the pharmacy front door. *Alternative:* through the grocery's back door and the alley (quieter, but darker and narrower) | ≈ 70 tiles | ~14 s / ~8 s | Medium: a small group of 4–6 near the pharmacy; the alley has 1–2 in the dark |
| Grocery ↔ Pharmacy | Along the main street (open, visible) or the back alley (hidden, cramped) | ≈ 45 tiles | ~9 s / ~5 s | Choice of risk |
| Any → Safehouse | Same streets back. The yard gate can be closed behind you | — | — | Zombies that followed you gather at the fence |

The safehouse is deliberately close to the grocery (first, easy trip). The pharmacy is far enough that the player must commit to the trip. Zombies **don't respawn endlessly**: each area has a fixed population that is partly refreshed each new "day" (after sleeping). Exact counts are tuned in Phase 4.

### 9.5 Phase 1 test map (not the final map)
Phase 1 uses a small **test yard** (~60 × 40 tiles): a walled square with a few wall segments and crates to test collision and corners, a small "safehouse" box with a doorway, and one Walker. Ashford Lane itself is built in Phase 4.

| Location | Danger | Typical loot | Gate |
|----------|--------|--------------|------|
| Safehouse | Safe | — | — |
| Residential houses | Low | food, water, bandages, scrap | open |
| Grocery store | Medium | food, water, batteries | open |
| Pharmacy | Medium | medicine, bandages | open |
| Abandoned vehicles | Low-medium (alarm risk) | scrap, pistol ammo, batteries | open |
| Warehouse | High, dark | scrap, shotgun, shotgun ammo, **radio component** | bolt cutters (objective) |
| Police checkpoint | High | ammo, rifle | post-MVP |

## 10. Items & loot

| ID | Name | Category | Stack | Use |
|----|------|----------|-------|-----|
| food_can | Canned food | food | 5 | Stash / objectives |
| water_bottle | Water | water | 5 | Stash / objectives |
| bandage | Bandage | medical | 5 | +25 HP over 3 s |
| medkit | Medicine kit | medical | 2 | +60 HP |
| ammo_pistol | Pistol rounds | ammo | 48 | — |
| ammo_shotgun | Shotgun shells | ammo | 24 | — |
| scrap | Scrap | material | 20 | Safehouse upgrades |
| battery | Battery | material | 6 | Flashlight |
| bolt_cutters | Bolt cutters | quest | 1 | Opens warehouse |
| radio_part | Radio component | quest | 1 | Radio repair |

**Searching takes time:** opening a container starts a search (shelf 0.8 s, cabinet/locker 1.2 s, car trunk 2.0 s) with a progress ring. Moving or getting hit cancels it. Searching makes low noise (60 px). This is the main moment when slow Walkers catch up.

**Quest items are never random.** The items the main objective chain needs are *guaranteed* in designated containers (see §11). Only ordinary extra resources are random.

Loot comes from **loot tables** (data files). Each container type references a table, for example `grocery_shelf` = 60% food, 30% water, 10% empty. A container rolls its contents **once**, the first time it's opened, and the result is remembered. Reopening it never re-rolls, so items can't be duplicated.

## 11. Safehouse & progression

Safehouse features: stash (unlimited storage), weapon rack, bed (full heal, ends the day/saves), radio desk (main objective), objective board.

**MVP objective chain** (every required item is guaranteed to exist and be reachable; see the table below):
1. *Stock up*: bring 5 food + 3 water to the stash.
2. *First aid*: find 2 medical items in the pharmacy.
3. *Cut the lock*: find bolt cutters (vehicle area / houses) to open the warehouse.
4. *Signal parts*: retrieve the radio component from the dark warehouse.
5. *Last signal*: return and repair the radio. MVP ending: a short broadcast reveals an evacuation route (hook for later content).

| Objective | Needs | Guaranteed supply (designated containers) |
|-----------|-------|------------------------------------------|
| Stock up | 5 food + 3 water | ≥ 7 food + ≥ 5 water across 4 grocery shelves and 2 house kitchens |
| First aid | 2 medical items | ≥ 4 medical items across 3 pharmacy containers |
| Cut the lock | bolt cutters | pickup-truck trunk on the main street, reachable **without** entering the warehouse |
| Signal parts | radio component | warehouse back-office locker (reachable once the gate is cut) |

Quest items can't be dropped or used up. If you die, they go into your backpack and are recovered with it.

## 12. UI screens

Main menu (New / Continue / Settings / Credits / Exit) · HUD (health, stamina, weapon, mag/reserve, noise meter, objective, interaction prompt, flashlight battery) · Inventory (list with icons, quantities, description, Use/Equip/Drop, slots used) · Stash transfer screen · Pause (Resume / Settings / Controls / Main menu) · Death screen (time survived, zombies killed, items lost, Retry / Main menu) · Settings (volume, fullscreen, key rebinding).

Style: dark, worn "field notebook / tape label" UI. One custom pixel font (OFL licence). Accent colours only for health (red), stamina (amber), objective (pale cyan).

## 13. Art direction

- Top-down 3/4 pixel art, 16 px tiles, characters ~16×24 px. Base resolution 640×360, scaled ×2/×3 crisp to 1280×720 / 1920×1080.
- Muted palette (greys, olive, rust, desaturated blue night). Saturated colour reserved for blood, UI warnings, loot highlights.
- Zombie silhouettes distinct per type (Walker hunched, Runner thin and leaning forward, Brute wide).

## 14. Audio direction

Wind/city ambience bed · distant groans (randomised, positional) · close groans as a warning cue · footsteps (player and zombie, surface-based later) · weapons, reloads, impacts · loot rustles · doors · UI clicks · safehouse ambience (rain on the roof, radio static). One low, tense music loop outside, a calmer loop in the safehouse.

## 15. Scope

**MVP (first release):** 1 map, Walker (+ Runner if time allows), bat, knife, pistol, shotgun, 10 items, 5-step objective chain, flashlight + 1 dark building, full menus, save/continue, Windows + web builds.

**Explicitly out of scope for first release:** multiplayer, accounts, ads, hunger/thirst/infection/sleep meters, crafting trees, procedural maps, story cutscenes, Android.

## 16. Decision log

| Date | Decision | By |
|------|----------|----|
| 2026-11-08 | Space = quick shove (cone push, 1.0 s cooldown, 15 stamina, no invincibility) | Owner |
| 2026-11-08 | Death = recoverable backpack. Stash, progression and equipped weapons kept; spent items not restored | Owner |
| 2026-11-08 | Engine Godot 4.7.2 Standard, GDScript only, Compatibility renderer for Windows + HTML5 | Owner |
| 2026-11-08 | Early browser export test in Phase 1, repeated when lighting is added | Owner |
| 2026-11-08 | Local Git repo first; GitHub remote (Extract001/humanVSzombie) connected later | Owner |
| 2026-11-08 | Interior darkness must be local (no whole-screen CanvasModulate); Subtract-light approach adopted after render test | Owner + Claude |
| 2026-11-08 | Player state enum includes SHOVING; no state grants invincibility | Owner |
| 2026-11-08 | Quest-critical items guaranteed in designated containers; ordinary loot stays random | Owner |
| 2026-11-08 | Walker values kept; changed only after multi-Walker / confined-space / looting gameplay tests | Owner |
| 2026-11-08 | Phase 3 data: single/open-field Walkers are easy for a perfect bot; danger comes from numbers + darkness. No values changed; awaiting owner's arena play-test | Claude (data) |
| 2026-11-08 | Phase 4 map built: 160×86 tiles; measured routes safehouse→grocery 24 tiles, safehouse→pharmacy 68 tiles, back alley grocery→pharmacy 48 tiles | Claude (implementation) |
| 2026-11-08 | Roofs cover building interiors only; walls and doors stay visible from outside | Claude (design detail) |
| 2026-11-08 | Medical/pharmacy symbol = green cross (the red-cross emblem is legally protected) | Claude (legal safety) |
| 2026-11-08 | Doors: Walkers bang on closed doors (warning sound) but can't open or break them; doors aren't part of the navigation mesh; locked gates are | Claude (implementation detail) |
| 2026-11-08 | **Redesign: day/night siege loop** with Echo, Heat, new zombie types, survivors + throwables; built in 5 playable slices; publishing after | Owner |
| 2026-11-08 | Slice 1 first-pass values (data/siege/siege_data.tres): day 300 s, dusk 45 s, night 150 s; horde 4 + 1.5/night + 0.75/Heat; pistol shot = +1 Heat; 3 windows, 30 HP per plank, max 3, start 2; Walker hits boards for 10 every 1.5 s. Measured with siege scenarios; **awaiting owner play-test** | Claude (data) |
| 2026-11-13 | Batch 2: **survivors** (Tomas Mechanic d2, Amara Doctor d3, Pip Scavenger d4, Hale Guard d5; radio call + green arrow + 2–4 zombies; escort by following on the nav mesh, no collisions, catch-up teleport > 260 px; rescue +150; loss chance 30% per broken window, ×0.5 with Hale, max one a night, seeded); **characters** (Rook; Mara 3 nights; Dex 150 lifetime kills; Kit 2500 score; Sol 3 lifetime rescues; stats via `Characters.apply` under perks; tint placeholder until Batch 3); **daily challenge** (seed and twist from the date, one life, own save `save_daily.json`, best per date, 30 days kept); **playtest mode** (local CSV + summary, rating 1–5). Survivors aren't attacked by zombies (kept simple; revisit after playtests) | Owner + Claude |
| 2026-11-13 | Owner asked for everything that keeps it from being addictive. Batch 1: **Brute** (180 HP, bite 20, shove resistance 0.85, 3× barricade damage, bursts unlocked doors after 4 bangs), **Screamer** (35 HP, scream 520 px calls zombies, no Heat), **night events** (none/brutes/screamers/fog/blackout/blood_moon, seeded per world+night, never twice in a row, night 1 calm), **supply drops** (day ≥ 2, seeded site ≥ 420 px from home, 3 + day/2 guards, Brute from day 4). Brute numbers lowered after measuring (220 HP/25 bite → 180/20; 1 Brute until night 5) | Owner + Claude |
| 2026-11-13 | Owner: "enhance the game as per your views to increase the rating". **Slice 2 built**: perk cards at dawn (13 perks, 1 of 3, up to 2 stacks each), **Your Echo** (your dead self carries your backpack: 150 HP, chase 72, kill it to drop the backpack; saved), **pump shotgun** (6 pellets × 20, 4 shells, 600 px noise = +1.25 Heat; house A wardrobe) and **fire axe** (45 damage, 35% knock-down; house C toolbox), weapon slots 3–4, opening radio transmission. Weapons never need bag space. Morning score screen was already in the fun pass | Owner + Claude |
| 2026-11-08 | Owner: "the game is very boring": empty walking, zombies not scary, weak fighting, unclear goals (all four). **Fun pass before new features**: street population around the player (10 near you on day 1, +1 per night, half come looking for you), fast **Lurchers** (chase 100 vs your walk 80 / run 140, 40 HP; 20% of street spawns, 25% of the horde), hit-stop + kill bursts + blood splats + kill crunch, score with kill streaks (x2..x5), loot/objective/night points, best score, red hurt vignette + heartbeat, goal arrow (SEARCH / STASH / CUT / RADIO / HOME / BOARD UP), day 150 s, dusk 30 s, searches ~40% faster. Walker values still unchanged | Owner + Claude |
| 2026-11-08 | Bed now = full heal + sleep until dusk + save (the day changes at dawn). The radio broadcast now promises the convoy after night 10 | Claude (design detail) |
| 2026-11-08 | Zombie group alert: spotting groan = 140 px noise; hearing a groan → investigate only (no chain reactions). Wander radius 80 px, dormant beyond 700 px | Claude (implementation detail) |
