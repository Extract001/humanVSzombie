@echo off
rem ============================================================
rem  LAST SIGNAL - Windows automated validation  [WIN-AUTO]
rem  Double-click this file. It runs YOUR Windows Godot 4.7.2:
rem    1. imports the project (finds broken files / script errors)
rem    2. runs the automated test suite (tests\test_runner.tscn)
rem    3. a bot plays the whole game to the ending on 5 world seeds, and a
rem       memory soak test repeats full sessions to catch leaks
rem  Optional: "validate.bat render" also runs the darkness + flashlight render
rem  test (a game window opens for a few seconds).
rem  Optional: "validate.bat scenarios" runs the Walker difficulty
rem  scenarios S1-S6 and the 40-zombie performance test.
rem  Optional: "validate.bat perf" runs the FPS benchmark on your GPU
rem  (1/10/20/40 Walkers, yard + dark room, real map, V-Sync on/off, flashlight),
rem  a quick comparison with the ANGLE graphics driver and a stutter check.
rem  Results: logs\perf_system.txt, perf_benchmark_opengl3.txt,
rem  perf_benchmark_opengl3_angle_quick.txt, perf_hitches.txt
rem  Result: logs\validate.log  +  VALIDATION PASSED / FAILED
rem ============================================================
setlocal
pushd "%~dp0.."
set "PROJECT=%CD%"
popd
if "%GODOT%"=="" set "GODOT=C:\Al-am\Game_engine\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" (
  echo Godot console executable not found:
  echo   %GODOT%
  echo Edit the GODOT path near the top of tools\validate.bat
  pause
  exit /b 2
)
if not exist "%PROJECT%\logs" mkdir "%PROJECT%\logs"
set "LOG=%PROJECT%\logs\validate.log"
set FAIL=0

echo LAST SIGNAL validation %DATE% %TIME% > "%LOG%"
"%GODOT%" --version >> "%LOG%" 2>&1

echo [1/4] Importing project...
rem First pass: Godot imports new or changed files. While it does, it may report the project theme
rem (or anything using a not-yet-imported file) as missing - that's expected once, so this pass goes to
rem logs\import.log and is not counted. The second pass must be clean.
"%GODOT%" --headless --path "%PROJECT%" --import > "%PROJECT%\logs\import.log" 2>&1
"%GODOT%" --headless --path "%PROJECT%" --import >> "%LOG%" 2>&1

echo [2/4] Running automated tests - about 15 seconds...
"%GODOT%" --headless --path "%PROJECT%" --fixed-fps 60 res://tests/test_runner.tscn >> "%LOG%" 2>&1
if errorlevel 1 set FAIL=1
findstr /C:"ALL TESTS PASSED" "%LOG%" >nul || set FAIL=1

echo [3/4] Full-game playthrough bot - 5 world seeds - and memory soak, about 30 seconds...
"%GODOT%" --headless --path "%PROJECT%" --fixed-fps 60 res://tests/scenarios/playthrough_bot.tscn >> "%LOG%" 2>&1
findstr /C:"PLAYTHROUGH PASSED" "%LOG%" >nul || set FAIL=1
"%GODOT%" --headless --path "%PROJECT%" --fixed-fps 60 res://tests/perf/soak_test.tscn >> "%LOG%" 2>&1
findstr /C:"SOAK TEST PASSED" "%LOG%" >nul || set FAIL=1

if /I "%~1"=="render" (
  echo [4/4] Render test - a window will open briefly...
  "%GODOT%" --path "%PROJECT%" res://tests/render/darkness_render_test.tscn >> "%LOG%" 2>&1
  findstr /B /C:"RENDER TEST PASSED" "%LOG%" >nul || set FAIL=1
  echo [4/4] Flashlight render test - a window will open briefly...
  "%GODOT%" --path "%PROJECT%" res://tests/render/flashlight_render_test.tscn >> "%LOG%" 2>&1
  findstr /C:"FLASHLIGHT RENDER TEST PASSED" "%LOG%" >nul || set FAIL=1
) else (
  echo [4/4] Render test skipped. Run "validate.bat render" to include it.
)

if /I "%~1"=="scenarios" (
  echo [+] Walker difficulty scenarios S1-S6 and 40-zombie performance - about 20 seconds...
  "%GODOT%" --headless --path "%PROJECT%" --fixed-fps 60 res://tests/scenarios/difficulty_scenarios.tscn >> "%LOG%" 2>&1
  findstr /C:"SCENARIOS COMPLETED" "%LOG%" >nul || set FAIL=1
  findstr /C:"S1 " /C:"S2 " /C:"S3 " /C:"S4 " /C:"S5 " /C:"S6 " /C:"frame time" "%LOG%"
)

if /I "%~1"=="perf" (
  echo [+] Performance check - about 6 minutes. A game window opens several times. Please don't touch it.
  echo     Plug in the charger, and close other heavy programs, including the Godot editor, first.
  echo [perf 1/4] Recording your graphics chips, screen refresh rate and power plan...
  powershell -NoProfile -Command "Get-CimInstance Win32_VideoController | Format-List Name,DriverVersion,CurrentRefreshRate,CurrentHorizontalResolution,CurrentVerticalResolution; powercfg /getactivescheme; Get-CimInstance Win32_Battery | Format-List BatteryStatus,EstimatedChargeRemaining" > "%PROJECT%\logs\perf_system.txt" 2>&1
  echo [perf 2/4] Full benchmark with the normal OpenGL driver - about 4 minutes...
  "%GODOT%" --path "%PROJECT%" res://tests/perf/perf_benchmark.tscn >> "%LOG%" 2>&1
  findstr /C:"PERF BENCHMARK COMPLETED" "%LOG%" >nul || set FAIL=1
  echo [perf 3/4] Quick benchmark with the ANGLE driver, Direct3D 11 - about 1 minute...
  "%GODOT%" --path "%PROJECT%" --rendering-driver opengl3_angle res://tests/perf/perf_benchmark.tscn -- --quick > "%PROJECT%\logs\perf_angle.log" 2>&1
  echo [perf 4/4] Stutter check: first flashlight, shot, effects and menus...
  "%GODOT%" --path "%PROJECT%" res://tests/perf/hitch_probe.tscn > "%PROJECT%\logs\perf_hitches.txt" 2>&1
  type "%PROJECT%\logs\perf_system.txt"
  type "%PROJECT%\logs\perf_benchmark_opengl3.txt"
  if exist "%PROJECT%\logs\perf_benchmark_opengl3_angle_quick.txt" type "%PROJECT%\logs\perf_benchmark_opengl3_angle_quick.txt"
  findstr /C:"HITCH" "%PROJECT%\logs\perf_hitches.txt"
  echo.
  echo Please send Claude these files from the logs folder:
  echo   perf_system.txt, perf_benchmark_opengl3.txt, perf_benchmark_opengl3_angle_quick.txt, perf_hitches.txt
)

findstr /C:"SCRIPT ERROR" /C:"Parse Error" "%LOG%" >nul && set FAIL=1
findstr /R /C:"^ERROR:" "%LOG%" >nul && set FAIL=1

echo.
findstr /C:"FAIL" /C:"ALL TESTS PASSED" /C:"TESTS FAILED" /C:"RENDER TEST" /C:"ERROR" /C:"PLAYTHROUGH" /C:"BOT seed" /C:"SOAK TEST" "%LOG%"
echo.
if "%FAIL%"=="0" (
  echo VALIDATION PASSED
  echo VALIDATION PASSED >> "%LOG%"
) else (
  echo VALIDATION FAILED - open logs\validate.log and send it to Claude
  echo VALIDATION FAILED >> "%LOG%"
)
echo.
pause
exit /b %FAIL%
