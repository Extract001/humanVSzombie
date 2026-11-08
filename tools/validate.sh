#!/usr/bin/env bash
# LAST SIGNAL — automated validation (Linux). Usage: tools/validate.sh [--render] [--scenarios]
# Set GODOT to your Godot 4.7.2 binary if it isn't at the default path.
set -u
GODOT="${GODOT:-/opt/godot/Godot_v4.7.2-stable_linux.x86_64}"
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT/logs"
LOG="$PROJECT/logs/validate_linux.log"
: > "$LOG"
fail=0

echo "[1/4] Importing project..." | tee -a "$LOG"
# First pass may report not-yet-imported files (e.g. the project theme) once: logged separately, not counted.
"$GODOT" --headless --path "$PROJECT" --import > "$PROJECT/logs/import.log" 2>&1
"$GODOT" --headless --path "$PROJECT" --import >> "$LOG" 2>&1

echo "[2/4] Running test suite..." | tee -a "$LOG"
"$GODOT" --headless --path "$PROJECT" --fixed-fps 60 res://tests/test_runner.tscn >> "$LOG" 2>&1 || fail=1
grep -q "ALL TESTS PASSED" "$LOG" || fail=1

echo "[3/4] Full-game playthrough bot (5 seeds) and memory soak..." | tee -a "$LOG"
"$GODOT" --headless --path "$PROJECT" --fixed-fps 60 res://tests/scenarios/playthrough_bot.tscn >> "$LOG" 2>&1 || fail=1
grep -q "PLAYTHROUGH PASSED" "$LOG" || fail=1
"$GODOT" --headless --path "$PROJECT" --fixed-fps 60 res://tests/perf/soak_test.tscn >> "$LOG" 2>&1 || fail=1
grep -q "SOAK TEST PASSED" "$LOG" || fail=1

if [[ " $* " == *" --render "* ]]; then
  echo "[4/4] Render test (local darkness)..." | tee -a "$LOG"
  xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path "$PROJECT" --rendering-driver opengl3 \
    res://tests/render/darkness_render_test.tscn >> "$LOG" 2>&1 || fail=1
  grep -q "^RENDER TEST PASSED" "$LOG" || fail=1
  echo "[4/4] Render test (flashlight in the warehouse)..." | tee -a "$LOG"
  xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path "$PROJECT" --rendering-driver opengl3 \
    res://tests/render/flashlight_render_test.tscn >> "$LOG" 2>&1 || fail=1
  grep -q "FLASHLIGHT RENDER TEST PASSED" "$LOG" || fail=1
else
  echo "[4/4] Render test skipped (use --render)" | tee -a "$LOG"
fi

if [[ " $* " == *" --scenarios "* ]]; then
  echo "[+] Walker difficulty scenarios S1-S6 + 40-zombie performance..." | tee -a "$LOG"
  "$GODOT" --headless --path "$PROJECT" --fixed-fps 60 res://tests/scenarios/difficulty_scenarios.tscn >> "$LOG" 2>&1 || fail=1
  grep -q "SCENARIOS COMPLETED" "$LOG" || fail=1
  sed -n '/WALKER DIFFICULTY/,/SCENARIOS COMPLETED/p' "$LOG"
fi

if grep -nE "SCRIPT ERROR|Parse Error|^ERROR:" "$LOG" | grep -v "audio_driver_alsa\|status < 0" ; then fail=1; fi
grep -E "PASS|FAIL|✗|ALL TESTS|TESTS FAILED|RENDER TEST|^BOT |SOAK (growth|long session node)" "$LOG" | grep -vE "^  PASS" || true
if [[ $fail -eq 0 ]]; then echo "VALIDATION PASSED" | tee -a "$LOG"; else echo "VALIDATION FAILED (see $LOG)" | tee -a "$LOG"; fi
exit $fail
