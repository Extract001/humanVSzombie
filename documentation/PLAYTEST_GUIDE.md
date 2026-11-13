# LAST SIGNAL — Playtest guide (for 3–5 friends)

The goal: find out **where people get bored, confused or frustrated** before adding more content.
You learn far more from watching 3 people play for 15 minutes than from any number of opinions.

Everything stays on your own computer. The game sends nothing anywhere.

---

## 1. Before the session (5 minutes)

1. Build or copy the game to the tester's PC (or let them use yours).
2. Check **Settings → Playtest mode** is ON. It's on by default in this early build.
3. Start a **New game** for each tester. If you want to keep your own save, back it up first: copy `save_v1.json` from the folder in section 4.
4. Have this page and a pen ready, or a phone for notes.

## 2. During the session (15 minutes per tester)

**What you say:** "It's a zombie survival game. Play it however you like for 15 minutes. Please think out loud: say what you're trying to do and what you think of it. I'm testing the game, not you."

**What you do:** sit behind them and **say nothing**. Don't explain controls and don't help unless they're completely stuck for over a minute. Every time you want to help is a design problem worth writing down.

**Write down the minute (from the clock or a stopwatch) when they:**

| Watch for | Example note |
|---|---|
| Look bored: sigh, check their phone, walk around aimlessly | "6:30 wandering, no idea where to go" |
| Get confused ("what do I do now?", ignore the arrow) | "2:10 didn't see the board-up prompt" |
| Get frustrated (die and groan, swear) | "9:00 Brute broke the window, felt unfair" |
| Have fun: laugh, lean in, say "oh no!" or "one more" | "11:20 rescued Tomas, said 'nice'" |
| Want to quit | "13:00 asked 'is that it?'" |

When they die, the game asks **"how fun was it so far? 1–5"**. Let them answer it themselves. They can also rate from the pause menu (Esc).

## 3. After the session (5 minutes): ask these, in this order

1. "Describe the game to a friend in one sentence."
2. "What was the best moment?"
3. "When were you bored, if ever?"
4. "Was anything confusing or unfair?"
5. "Would you play again tomorrow? Why or why not?"
6. "What would make you play it for an hour?"

Write the answers word for word, especially the surprising ones.

## 4. The automatic log

The game writes two files in its user folder:

- **Windows:** `%APPDATA%\Godot\app_userdata\LAST SIGNAL\`. Paste that into the Explorer address bar.
- **Linux:** `~/.local/share/godot/app_userdata/LAST SIGNAL/`

The files:

| File | What's in it |
|---|---|
| `playtest_summary.txt` | One short block per session: how long, deaths and **what killed them**, nights reached, score, survivors rescued, **quiet minutes** (minutes with no kills and under 40 m walked = possible boredom) and the rating. Read this first. |
| `playtest_log.csv` | Every event as a table. Open it in Excel or Google Sheets. One `minute` row per minute of play (kills, metres walked, `quiet`, `in_safehouse`), plus `death`, `day`/`dusk`/`night`, `objective`, `perk`, `survivor_rescued`, `survivor_lost`, `unlock`, `rating`, `session_start`/`session_end`. |

**How to read it:**

- **Many `quiet` minutes in a row** means the game gave them nothing to do. Look at the `x,y` columns to see where they were. Tile 78,71 is the safehouse.
- **Many deaths to the same thing** (`detail` = `brute`, `walker`, `lurcher`) means that thing may be unfair.
- **`session_end` soon after a death** means the death made them quit.
- **Ratings by tester** tell you which kind of player enjoys it.

To start fresh, delete or rename the two files between testers, or keep them: each session has its own `session` id.

## 5. Bring it back

Send me (Claude) the `playtest_summary.txt` files, your notes and the answers. Copy and paste is fine. We'll decide the next changes from what the players actually did, not from guesses.

## 6. Turning it off

**Settings → Playtest mode** off: no more log and no rating questions.
