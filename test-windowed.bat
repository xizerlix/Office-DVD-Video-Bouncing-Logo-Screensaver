@echo off
REM ====================================================================
REM   DVD Screensaver — windowed test mode
REM   Runs in an 820x620 resizable window on the primary monitor. This
REM   is the easiest way to verify the animation works without taking
REM   over your whole desktop. Click anywhere or press any key to close.
REM ====================================================================

setlocal
set EXE=%~dp0bin\DvdScreensaver.exe
if not exist "%EXE%" (
    echo ERROR: %EXE% not found. Run build.bat first.
    pause
    exit /b 1
)
start "" "%EXE%" /w
endlocal
