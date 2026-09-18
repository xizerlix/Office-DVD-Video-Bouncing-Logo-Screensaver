@echo off
setlocal

REM ====================================================================
REM   DVD Screensaver -- uninstall
REM
REM   Removes the .scr from C:\Windows\System32 and clears registry.
REM   Must be run as Administrator.
REM
REM   Every step is mirrored to uninstall.log so we can see what
REM   happened even if the cmd window is dismissed quickly.
REM ====================================================================

set DEST=%WINDIR%\System32\DvdScreensaver.scr
set DEST_DIR=%WINDIR%\System32
set NAME=DvdScreensaver
set LOG=%~dp0uninstall.log

> "%LOG%" echo --- uninstall.bat started at %date% %time% ---

net session >nul 2>&1
if errorlevel 1 (
    echo ERROR: Administrator rights required.
    echo Right-click uninstall.bat, then "Run as administrator".
    pause
    exit /b 1
)

echo [1/5] Stopping running screensaver processes...
taskkill /F /IM DvdScreensaver.exe >> "%LOG%" 2>&1
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='DvdScreensaver.exe'\" ^| ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate }" >> "%LOG%" 2>&1
timeout /t 2 /nobreak >nul

echo [2/5] Removing registry entries...
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Screensavers\%NAME%" /f >> "%LOG%" 2>&1
reg delete "HKCU\Software\TheOfficeScreensaver" /f >> "%LOG%" 2>&1
reg delete "HKCU\Control Panel\Desktop" /v SCRNSAVE.EXE /f >> "%LOG%" 2>&1
reg add "HKCU\Control Panel\Desktop" /v ScreenSaveActive /d "0" /f >> "%LOG%" 2>&1

echo [3/5] Looking for processes holding the .scr open...
powershell -NoProfile -Command "$dst = '%DEST%'; $open = Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -eq $dst } | Select-Object ProcessId, Name; if ($open) { 'Open handles on the .scr file:'; $open | Format-Table -AutoSize } else { 'No process has the .scr mapped as its executable.' }" >> "%LOG%" 2>&1
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*DvdScreensaver*' } | Select-Object ProcessId, Name, CommandLine | Format-Table -AutoSize | Out-String -Width 4096" >> "%LOG%" 2>&1

echo [4/5] Removing %DEST%...
if exist "%DEST%" (
    >> "%LOG%" echo [4/5] renaming .scr -^> .scr.removing
    ren "%DEST%" "DvdScreensaver.scr.removing" >> "%LOG%" 2>&1
)
if exist "%DEST_DIR%\DvdScreensaver.scr.removing" (
    >> "%LOG%" echo [4/5] deleting .scr.removing
    del /F /Q "%DEST_DIR%\DvdScreensaver.scr.removing" >> "%LOG%" 2>&1
)

if exist "%DEST_DIR%\DvdScreensaver.scr.old" (
    >> "%LOG%" echo [4/5] renaming .scr.old -^> .scr.old.removing
    ren "%DEST_DIR%\DvdScreensaver.scr.old" "DvdScreensaver.scr.old.removing" >> "%LOG%" 2>&1
)
if exist "%DEST_DIR%\DvdScreensaver.scr.old.removing" (
    >> "%LOG%" echo [4/5] deleting .scr.old.removing
    del /F /Q "%DEST_DIR%\DvdScreensaver.scr.old.removing" >> "%LOG%" 2>&1
)

echo [5/5] Final state:
if exist "%DEST%" (
    echo.
    echo WARNING: %DEST% is still on disk. Something has it locked.
    echo Trying takeown + scheduled removal on next reboot...
    >> "%LOG%" echo [warn] %DEST% still present after rename+delete

    takeown /F "%DEST%" /A >> "%LOG%" 2>&1
    icacls "%DEST%" /reset >> "%LOG%" 2>&1

    powershell -NoProfile -Command "$dst = '%DEST%'; $pending = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'; $cur = (Get-ItemProperty -Path $pending -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations; if ($null -eq $cur) { $cur = @() } else { $cur = @($cur) }; $cur += @(\"`??\\$($dst -replace '/','\\')`\", '`??\\DvdScreensaver.scr.pending\`'); New-ItemProperty -Path $pending -Name PendingFileRenameOperations -Value $cur -PropertyType MultiString -Force | Out-Null" >> "%LOG%" 2>&1
    echo.
    echo Scheduled for deletion on next reboot. Restart Windows to finish.
) else (
    echo SUCCESS: %DEST% removed.
    >> "%LOG%" echo [ok] %DEST% removed
)

if exist "%DEST_DIR%\DvdScreensaver.scr.old" (
    echo NOTE: %DEST_DIR%\DvdScreensaver.scr.old is still there, will be removed on reboot.
    powershell -NoProfile -Command "$dst = '%DEST_DIR%\DvdScreensaver.scr.old'; $pending = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'; $cur = (Get-ItemProperty -Path $pending -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations; if ($null -eq $cur) { $cur = @() } else { $cur = @($cur) }; $cur += @(\"`??\\$($dst -replace '/','\\')`\", '`??\\DvdScreensaver.scr.old.pending\`'); New-ItemProperty -Path $pending -Name PendingFileRenameOperations -Value $cur -PropertyType MultiString -Force | Out-Null" >> "%LOG%" 2>&1
)

echo.
echo Log: %LOG%
echo.

>> "%LOG%" echo --- uninstall.bat finished at %date% %time% ---
pause
endlocal
