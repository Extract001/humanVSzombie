@echo off
rem ============================================================
rem  LAST SIGNAL - Windows automated validation  [WIN-AUTO]
rem  Double-click this file. It runs YOUR Windows Godot 4.7.2:
rem    1. imports the project (finds broken files / script errors)
rem    2. runs the automated test suite (tests\test_runner.tscn)
rem  Optional: "validate.bat render" also runs the darkness + flashlight render
rem  test (a game window opens for a few seconds).
rem  Optional: "validate.bat scenarios" runs the Walker difficulty
rem  scenarios S1-S6 and the 40-zombie performance test.
rem  Optional: "validate.bat perf" runs the FPS benchmark on your GPU
rem  (1/10/20/40 Walkers, yard + dark room, V-Sync on/off) and saves
rem  logs\perf_benchmark.txt.
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

echo [1/3] Importing project...
rem First pass: Godot imports new or changed files. While it does, it may report the project theme
rem (or anything using a not-yet-imported file) as missing - that's expected once, so this pass goes to
rem logs\import.log and is not counted. The second pass must be clean.
"%GODOT%" --headless --path "%PROJECT%" --import > "%PROJECT%\logs\import.log" 2>&1
"%GODOT%" --headless --path "%PROJECT%" --import >> "%LOG%" 2>&1

echo [2/3] Running automated tests (about 10 seconds)...
"%GODOT%" --headless --path "%PROJECT%" --fixed-fps 60 res://tests/test_runner.tscn >> "%LOG%" 2>&1
if errorlevel 1 set FAIL=1
findstr /C:"ALL TESTS PASSED" "%LOG%" >nul || set FAIL=1

if /I "%~1"=="render" (
  echo [3/3] Render test - a window will open briefly...
  "%GODOT%" --path "%PROJECT%" res://tests/render/darkness_render_test.tscn >> "%LOG%" 2>&1
  findstr /B /C:"RENDER TEST PASSED" "%LOG%" >nul || set FAIL=1
  echo [3/3] Flashlight render test - a window will open briefly...
  "%GODOT%" --path "%PROJECT%" res://tests/render/flashlight_render_test.tscn >> "%LOG%" 2>&1
  findstr /C:"FLASHLIGHT RENDER TEST PASSED" "%LOG%" >nul || set FAIL=1
) else (
  echo [3/3] Render test skipped. Run "validate.bat render" to include it.
)

if /I "%~1"=="scenarios" (
  echo [+] Walker difficulty scenarios S1-S6 and 40-zombie performance - about 20 seconds...
  "%GODOT%" --headless --path "%PROJECT%" --fixed-fps 60 res://tests/scenarios/difficulty_scenarios.tscn >> "%LOG%" 2>&1
  findstr /C:"SCENARIOS COMPLETED" "%LOG%" >nul || set FAIL=1
  findstr /C:"S1 " /C:"S2 " /C:"S3 " /C:"S4 " /C:"S5 " /C:"S6 " /C:"frame time" "%LOG%"
)

if /I "%~1"=="perf" (
  echo [+] Performance benchmark - a game window opens for about 2 minutes. Please don't touch it.
  echo     Plug in the charger, and close other heavy programs first.
  "%GODOT%" --path "%PROJECT%" res://tests/perf/perf_benchmark.tscn >> "%LOG%" 2>&1
  findstr /C:"PERF BENCHMARK COMPLETED" "%LOG%" >nul || set FAIL=1
  type "%PROJECT%\logs\perf_benchmark.txt"
)

findstr /C:"SCRIPT ERROR" /C:"Parse Error" "%LOG%" >nul && set FAIL=1
findstr /R /C:"^ERROR:" "%LOG%" >nul && set FAIL=1

echo.
findstr /C:"FAIL" /C:"ALL TESTS PASSED" /C:"TESTS FAILED" /C:"RENDER TEST" /C:"ERROR" "%LOG%"
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
