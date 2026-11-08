@echo off
rem ============================================================
rem  LAST SIGNAL - run the browser (HTML5) build locally  [WEB-EXPORT]
rem  Browsers can't run Godot web games from a double-clicked file,
rem  so this starts a tiny local web server (needs Python) and opens
rem  Chrome/Edge at http://localhost:8060/index.html?perf
rem  Close this window to stop the server.
rem ============================================================
setlocal
cd /d "%~dp0..\export\web"
if not exist index.html (
  echo No web build found in export\web.
  pause
  exit /b 1
)
set "PY="
where python >nul 2>nul && set "PY=python"
if "%PY%"=="" where py >nul 2>nul && set "PY=py"
if "%PY%"=="" (
  echo Python was not found. Use Godot's "Run in Browser" instead - see README.md.
  pause
  exit /b 1
)
echo Starting local server on http://localhost:8060 ...
echo Close this window when you are done testing.
start "" cmd /c "timeout /t 2 >nul & start http://localhost:8060/index.html?perf"
%PY% -m http.server 8060 --bind 127.0.0.1
