@echo off
REM ====================================================================
REM   DVD Screensaver — fullscreen preview
REM   Runs the screensaver right now, full-screen, on every monitor.
REM   Move the mouse or click to exit.
REM
REM   If nothing seems to happen, try test-windowed.bat first — it runs
REM   in a normal resizable window and is easier to see.
REM ====================================================================

setlocal
set EXE=%~dp0bin\DvdScreensaver.exe
if not exist "%EXE%" (
    echo ERROR: %EXE% not found. Run build.bat first.
    pause
    exit /b 1
)
echo Starting DVD screensaver in fullscreen...
echo Move the mouse, click, or press any key to exit.
start "" "%EXE%" /s
endlocal
