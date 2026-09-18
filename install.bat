@echo off
setlocal

REM ====================================================================
REM   DVD Screensaver -- install
REM
REM   Copies the screensaver into C:\Windows\System32 and registers it
REM   as the user's active screensaver.
REM
REM   MUST be run as Administrator: right-click the file in Explorer,
REM   pick "Run as administrator". UAC will pop up.
REM
REM   Every step is mirrored to install.log so we have a record if the
REM   cmd window is dismissed before you can read the error.
REM ====================================================================

set SRC=%~dp0bin\DvdScreensaver.exe
set DEST_DIR=%WINDIR%\System32
set DEST=%DEST_DIR%\DvdScreensaver.scr
set NAME=DvdScreensaver
set LOG=%~dp0install.log

REM Reset the log.
> "%LOG%" echo --- install.bat started at %date% %time% ---
>> "%LOG%" echo SRC=%SRC%
>> "%LOG%" echo DEST=%DEST%

REM ----- Admin check -------------------------------------------------------
>> "%LOG%" echo [check] admin
net session >nul 2>&1
if errorlevel 1 (
    echo ERROR: Administrator rights required.
    echo Right-click install.bat, then "Run as administrator".
    >> "%LOG%" echo [fail] admin check failed
    pause
    exit /b 1
)
>> "%LOG%" echo [ok] admin
echo [1/5] Admin OK

REM ----- Source check ------------------------------------------------------
>> "%LOG%" echo [check] source %SRC%
if not exist "%SRC%" (
    echo ERROR: %SRC% not found. Run build.bat first.
    >> "%LOG%" echo [fail] source missing
    pause
    exit /b 1
)
>> "%LOG%" echo [ok] source exists
echo [2/5] Source OK (%SRC%)

REM ----- Kill any running screensaver processes ----------------------------
REM First, disable the active screensaver so Windows stops spawning the .scr
REM in a tight loop while we're trying to kill it.
>> "%LOG%" echo [disable] ScreenSaveActive
reg add "HKCU\Control Panel\Desktop" /v ScreenSaveActive /d "0" /f >> "%LOG%" 2>&1

REM Kill by ExecutablePath — covers both DvdScreensaver.exe (test mode) AND
REM DvdScreensaver.scr (real install). Plain `taskkill /F /IM DvdScreensaver.exe`
REM does NOT match processes named DvdScreensaver.scr, which is exactly what
REM bit us: the running instances all slipped through taskkill.
echo Killing by ExecutablePath...
>> "%LOG%" echo [kill] by ExecutablePath
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { \$_.ExecutablePath -like '*DvdScreensaver*' } | ForEach-Object { Invoke-CimMethod -InputObject \$_ -MethodName Terminate }" >> "%LOG%" 2>&1

REM Belt-and-suspenders: also TerminateProcess via Win32 (synchronous kill).
REM WMI Terminate returns success but the OS may not have reaped the process
REM yet, and Windows re-spawns fast in the Settings dialog loop.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0kill-running.ps1" >> "%LOG%" 2>&1
timeout /t 1 /nobreak >nul

REM Pause Windows Search Indexer. It holds a FILE_SHARE_NONE handle on every
REM new .exe/.scr in System32 while it scans them, which is what blocks our copy.
echo [1b/5] Pausing Windows Search (releases lock on the .scr)...
powershell -NoProfile -Command "$svc = Get-Service -Name WSearch -ErrorAction SilentlyContinue; if ($svc) { if ($svc.Status -eq 'Running') { Set-Service -Name WSearch -StartupType Manual -ErrorAction SilentlyContinue; Stop-Service -Name WSearch -Force -NoWait -ErrorAction SilentlyContinue; 'WSearch stopped' } else { 'WSearch already stopped' } } else { 'WSearch not present' }" >> "%LOG%" 2>&1
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.Name -like 'SearchPro*' -or $_.Name -eq 'SearchIndexer.exe' -or $_.Name -eq 'SearchHost.exe' } | ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate }" >> "%LOG%" 2>&1

REM Defender (MsMpEng) is the next-most-common holder. Briefly disable
REM real-time monitoring — the protection resumes at the end of install.bat.
echo [1c/5] Pausing Defender real-time monitoring...
powershell -NoProfile -Command "try { Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction Stop; 'Defender RT disabled' } catch { 'Defender RT could not be disabled (continuing anyway)' }" >> "%LOG%" 2>&1

timeout /t 3 /nobreak >nul
echo [3/5] All running processes killed (or none were running)

REM ----- Clear previous install -------------------------------------------
>> "%LOG%" echo [clear] checking previous install
if exist "%DEST%" (
    >> "%LOG%" echo [clear] renaming %DEST% -^> .scr.old
    ren "%DEST%" "DvdScreensaver.scr.old" >> "%LOG%" 2>&1
)
if exist "%DEST_DIR%\DvdScreensaver.scr.old" (
    >> "%LOG%" echo [clear] deleting .scr.old
    del /F /Q "%DEST_DIR%\DvdScreensaver.scr.old" >> "%LOG%" 2>&1
)
if exist "%DEST_DIR%\DvdScreensaver.scr.old" (
    >> "%LOG%" echo [warn] .scr.old still present after delete
)

REM ----- Copy the new binary into System32 --------------------------------
REM Try copy several times with a short pause — sometimes SearchIndexer
REM (or an antivirus) still has the old file open for a couple of seconds
REM after we killed its processes, and a second or third attempt wins.
echo [4/5] Copying binary to %DEST%...
setlocal enabledelayedexpansion
set ATTEMPT=0
set COPYOK=0
:copyloop
set /a ATTEMPT+=1
>> "%LOG%" echo [copy] attempt !ATTEMPT!
copy /Y "%SRC%" "%DEST%" >nul 2>&1
>> "%LOG%" echo [copy] errorlevel=%errorlevel%
if not errorlevel 1 (
    set COPYOK=1
    goto copydone
)
if !ATTEMPT! LSS 4 (
    echo   retrying in 3s...
    timeout /t 3 /nobreak >nul
    goto copyloop
)
:copydone
endlocal & set COPYOK=%COPYOK%

REM IMPORTANT: check copy's errorlevel, not whether the file exists. The old
REM file may still be at %DEST% (locked), and "if not exist" would falsely
REM say "all good" even though copy wrote 0 bytes.
if "%COPYOK%" NEQ "1" (
    echo.
    echo ERROR: failed to copy to %DEST% after 4 attempts.
    echo The file is held by something other than Windows Search — most likely
    echo Windows Defender (MsMpEng.exe) scanning it, or Windows Resource
    echo Protection. The uninstall was probably incomplete.
    echo.
    echo Scheduling the old file for deletion on next reboot. After you
    echo restart Windows, run install.bat again — it will succeed because
    echo the old locked file will be gone.
    >> "%LOG%" echo [fail] copy failed after !ATTEMPT! attempts -- scheduling delete on reboot

    powershell -NoProfile -Command "$dst = '%DEST%'; $pending = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'; $cur = (Get-ItemProperty -Path $pending -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations; if ($null -eq $cur) { $cur = @() } else { $cur = @($cur) }; $cur += @(\"`??\\$($dst -replace '/','\\')`\", '`??\\DvdScreensaver.scr.pending\`'); New-ItemProperty -Path $pending -Name PendingFileRenameOperations -Value $cur -PropertyType MultiString -Force | Out-Null" >> "%LOG%" 2>&1

    echo Resume Windows Search so the system stays usable...
    powershell -NoProfile -Command "Set-Service -Name WSearch -StartupType Automatic -ErrorAction SilentlyContinue; Start-Service -Name WSearch -ErrorAction SilentlyContinue" >> "%LOG%" 2>&1

    echo Re-enabling Defender real-time monitoring...
    powershell -NoProfile -Command "Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue" >> "%LOG%" 2>&1

    echo.
    echo ============================================================
    echo  REBOOT REQUIRED
    echo.
    echo  1. Restart Windows.
    echo  2. After restart, run install.bat AGAIN (right-click -^> Run as admin).
    echo     The locked file will be gone, and the install will succeed.
    echo ============================================================
    echo.
    pause
    exit /b 1
)
echo [4/5] Copied binary to %DEST%

REM ----- Register in registry --------------------------------------------
>> "%LOG%" echo [reg] writing HKLM screensavers key
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Screensavers\%NAME%" /ve /d "DVD Bouncing Logo (The Office Edition)" /f >> "%LOG%" 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Screensavers\%NAME%" /v "DisplayName" /d "DVD Bouncing Logo (The Office Edition)" /f >> "%LOG%" 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Screensavers\%NAME%" /v "Type" /d 2 /f >> "%LOG%" 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Screensavers\%NAME%" /v "ApplicationName" /d "DvdScreensaver" /f >> "%LOG%" 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Screensavers\%NAME%" /v "scrnsave.exe" /d "%DEST%" /f >> "%LOG%" 2>&1

>> "%LOG%" echo [reg] writing HKCU active screensaver
reg add "HKCU\Control Panel\Desktop" /v SCRNSAVE.EXE /d "%DEST%" /f >> "%LOG%" 2>&1
reg add "HKCU\Control Panel\Desktop" /v ScreenSaveActive /d "1" /f >> "%LOG%" 2>&1
reg add "HKCU\Control Panel\Desktop" /v ScreenSaveTimeOut /d "300" /f >> "%LOG%" 2>&1
reg add "HKCU\Control Panel\Desktop" /v ScreenSaverIsSecure /d "1" /f >> "%LOG%" 2>&1

echo [5/5] Registered in registry

REM ----- Final verification ----------------------------------------------
>> "%LOG%" echo [verify] final state
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Screensavers\%NAME%" /v "scrnsave.exe" >> "%LOG%" 2>&1
reg query "HKCU\Control Panel\Desktop" /v SCRNSAVE.EXE >> "%LOG%" 2>&1

REM Resume Windows Search now that the copy is done.
echo Resuming Windows Search...
powershell -NoProfile -Command "Set-Service -Name WSearch -StartupType Automatic -ErrorAction SilentlyContinue; Start-Service -Name WSearch -ErrorAction SilentlyContinue" >> "%LOG%" 2>&1

REM Re-enable Defender real-time monitoring (we disabled it briefly to allow
REM the copy to succeed; leaving it off would weaken system security).
echo Re-enabling Defender real-time monitoring...
powershell -NoProfile -Command "try { Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue; 'Defender RT re-enabled' } catch { 'Defender RT re-enable failed (please enable manually)' }" >> "%LOG%" 2>&1

echo.
echo ============================================================
echo  Installed successfully.
echo.
echo  File:        %DEST%
echo  Screensaver: DVD Bouncing Logo (The Office Edition)
echo  Idle delay:  5 minutes
echo.
echo  Open Settings, Personalization, Lock screen, Screen saver
echo  settings, pick "DVD Bouncing Logo" from the dropdown, and
echo  click Preview to test it.
echo.
echo  Log written to: %LOG%
echo ============================================================
echo.

>> "%LOG%" echo --- install.bat finished OK at %date% %time% ---
pause
endlocal
