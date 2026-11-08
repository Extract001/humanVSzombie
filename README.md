# LAST SIGNAL

A top-down 2D zombie survival game made with **Godot 4.7.2** and **GDScript**.

> Status: **Phase 10 — Save system.** Phases 4–10 are IMPLEMENTED and TESTED by automated checks (Linux + automated browser test) and wait for your Windows play-tests. Phase 2 VERIFIED. Phase 3 behaviour passed but **not VERIFIED** (30 FPS performance issue still open: please run `validate.bat perf` and try V-Sync off in Settings). All art, sound and music is original, made from code (`tools/asset_generators/`).

## Requirements
- Godot 4.7.2-stable, Standard edition (installed at `C:\Al-am\Game_engine\`)
- Git (recommended)
- Python (only for `tools\serve_web.bat`; optional)

## Opening and playing the project
1. Run `C:\Al-am\Game_engine\Godot_v4.7.2-stable_win64.exe`.
2. In the Project Manager, click **Import** (top left), browse to `C:\Al-am\Game_development\project.godot`, then click **Import & Edit**.
3. The first time, Godot imports the assets (a progress bar for a few seconds). This creates a hidden `.godot` folder: that's normal, and Git ignores it.
4. Press **F5** (or the ▶ **Run Project** button, top right) to play. The game opens on the main menu; click **New game**.
   Settings (volume, fullscreen, V-Sync, FPS counter, key rebinding) are saved in `%APPDATA%\Godot\app_userdata\LAST SIGNAL\settings.cfg`.
   Your game is saved when you walk into the safehouse, sleep, die, or quit to the menu from the safehouse (`save_v1.json` in the same folder). **Continue** loads it.
5. To stop: close the game window, or press **F8** in the editor.

## Controls
| Action | Key | Works in Phase 1? |
|--------|-----|-------------------|
| Move | W A S D | ✅ |
| Run | Shift (needs ≥ 10 stamina to start) | ✅ |
| Aim / facing | Mouse (crosshair) | ✅ |
| Attack / fire | Left mouse (bat: hold to keep swinging; pistol: one shot per click) | ✅ |
| Aim steady | Right mouse | Later (not yet built) |
| Quick shove | Space (15 stamina, 1 s cooldown) | ✅ |
| Reload | R (also automatic when you fire an empty pistol) | ✅ |
| Interact (doors, gates, containers, stash, bed, radio, objective board) | E, when the prompt appears (in reach and facing it) | ✅ |
| Flashlight on/off | F | Phase 6 |
| Weapons | 1 = bat, 2 = pistol, mouse wheel cycles | ✅ |
| Inventory (Use / Drop) | Tab / I | Phase 5 |
| Pause (Resume / Settings / Controls / Main menu) | Esc | ✅ Phase 8 |

Change keys in Godot: **Project → Project Settings → Input Map** tab.

## Checking the project

| What | How | Category |
|------|-----|----------|
| Automated checks on **your Windows** Godot | Double-click `tools\validate.bat`. Wait for `VALIDATION PASSED` or `FAILED`. The log is saved to `logs\validate.log` | `[WIN-AUTO]` |
| Same, plus the darkness render test (a window opens briefly) | Open Command Prompt in `tools\` and run `validate.bat render` | `[WIN-AUTO]` |
| Browser build | Double-click `tools\serve_web.bat`. It opens `http://localhost:8060/index.html?perf` in your browser | `[WEB-EXPORT]` |
| Walker difficulty scenarios S1–S6 + 40-zombie performance | Command Prompt in `tools\` → `validate.bat scenarios` (about 20 s; prints a results table) | `[WIN-AUTO]` |
| Play the six difficulty arenas yourself | In Godot's FileSystem panel open `scenes/debug/arena_playground.tscn`, press **F6** (Run Current Scene). In the game press **F1–F6** to switch arenas | `[WIN-PLAY]` |
| Linux automated checks (Claude) | `tools/validate.sh --render --scenarios` | `[LINUX-AUTO]` |

**If `serve_web.bat` says Python isn't found:** in the Godot editor, go to **Editor → Manage Export Templates → Download and Install** (one time, about 1.3 GB). Then use the one-click deploy button in the top-right toolbar (it appears once export templates are installed; the project already has a **Web** preset) and choose **Run in Browser**.

## Project layout
```
scenes/      ui/main_menu.tscn (start scene) · main/game.tscn · player/ · zombies/ · world/ (test_yard, dark_zone) · ui/ · debug/ (arena playground)
scripts/     autoload/ (audio_manager, noise_system, game_state) · components/ · player/ · weapons/ · inventory/ · zombies/ · world/ (dark_zone, navigation_baker) · ui/ · main/ · data/ · debug/
scenes/world/ashford_lane.tscn is the game map (the old test_yard is kept for tests).
data/        player/player_stats.tres · zombies/walker.tres · weapons/bat.tres, pistol.tres   ← tweak numbers here
assets/      sprites/ · tiles/ · fonts/ · ui/ · audio/sfx/ · audio/music/   (original art, sound and music)
tests/       automated tests (test_runner.tscn) · render/ (darkness render test) · scenarios/ (difficulty S1–S6)
tools/       validate.bat · validate.sh · serve_web.bat
export/      build output (not tracked by Git)
documentation/
```
**Tweaking values without code:** in the Godot **FileSystem** panel (bottom left), double-click `data/player/player_stats.tres` or `data/zombies/walker.tres`. The numbers appear in the **Inspector** (right side). Change them and press F5.

## Git setup (you run these once, on Windows)

**1. Check Git is installed.** Open **Command Prompt** (Start menu → type `cmd` → Enter) and run:
```
git --version
```
Expected: something like `git version 2.4x.x.windows.1`.
If you get *"'git' is not recognized"*, install **Git for Windows** from https://git-scm.com/download/win (free; default options are fine), then close and reopen Command Prompt.

**2. Create the repository with two commits (Phase 0 documents first, then the Phase 1 prototype):**
```
cd /d C:\Al-am\Game_development
git init -b main
git config user.name "Extract001"
git config user.email "hunarali912@gmail.com"
git add README.md CLAUDE.md CHANGELOG.md ASSET_LICENSES.md .gitignore .gitattributes documentation
git commit -m "Phase 0: planning documents v0.3"
git add .
git status
git commit -m "Phases 1-4: prototype, combat, zombie AI, Ashford Lane"
git log --oneline
```
Expected: `git log --oneline` shows two commits. `git status` before the second commit lists the new project files; `export/`, `logs/` and `.godot/` should **not** appear (they're ignored).
Line-ending warnings (`LF will be replaced by CRLF`) are harmless.
*(This README already describes Phase 1. It's in the first commit because the file also holds the Git instructions.)*

**3. Later, to connect GitHub** (not now):
```
git remote add origin https://github.com/Extract001/humanVSzombie.git
git push -u origin main
```
Check that the repository is set to **Private** on GitHub first if you don't want it public.

## Documentation
- [Game Design Document](documentation/GDD.md)
- [Technical Architecture](documentation/TECHNICAL_ARCHITECTURE.md)
- [Development Roadmap](documentation/DEVELOPMENT_ROADMAP.md)
- [QA Checklist](documentation/QA_CHECKLIST.md)
- [Asset Licences](ASSET_LICENSES.md) · [Changelog](CHANGELOG.md)
