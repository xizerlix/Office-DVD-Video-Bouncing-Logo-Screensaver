@echo off
setlocal

REM ====================================================================
REM   Force-remove DvdScreensaver.scr from System32
REM
REM   Use this if uninstall.bat refuses because the file is held open
REM   by an antivirus, Windows Search Indexer, or some other service
REM   that won't release the handle. This script:
REM     1) Kills any running screensaver process.
REM     2) Takes ownership of the file.
REM     3) Resets ACLs so administrators have full control.
REM     4) Tries to rename + delete (rename works on more locked
REM        files than plain delete does).
REM     5) If everything else fails, schedules the file for deletion
REM        on the next reboot via PendingFileRenameOperations.
REM
REM   Run as Administrator.
REM ====================================================================

set DEST=%WINDIR%\System32\DvdScreensaver.scr
set DEST_DIR=%WINDIR%\System32
set LOG=%~dp0force-remove.log

> "%LOG%" echo --- force-remove started %date% %time% ---

net session >nul 2>&1
if errorlevel 1 (
    echo ERROR: Administrator rights required.
    pause
    exit /b 1
)

echo [1/6] Killing any running screensaver processes...
taskkill /F /IM DvdScreensaver.exe >> "%LOG%" 2>&1
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='DvdScreensaver.exe'\" ^| ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate }" >> "%LOG%" 2>&1
timeout /t 2 /nobreak >nul

echo [2/6] Taking ownership of %DEST% (if it exists)...
if exist "%DEST%" (
    takeown /F "%DEST%" /A >> "%LOG%" 2>&1
    icacls "%DEST%" /reset >> "%LOG%" 2>&1
    icacls "%DEST%" /grant *S-1-5-32-544:F /T /C /Q >> "%LOG%" 2>&1
    icacls "%DEST%" /grant *S-1-5-18:F /T /C /Q >> "%LOG%" 2>&1
)

echo [3/6] Trying rename + delete...
if exist "%DEST%" (
    ren "%DEST%" "DvdScreensaver.scr.removing" >> "%LOG%" 2>&1
)
if exist "%DEST_DIR%\DvdScreensaver.scr.removing" (
    del /F /Q "%DEST_DIR%\DvdScreensaver.scr.removing" >> "%LOG%" 2>&1
)

echo [4/6] Cleaning up old leftovers (.scr.old)...
if exist "%DEST_DIR%\DvdScreensaver.scr.old" (
    takeown /F "%DEST_DIR%\DvdScreensaver.scr.old" /A >> "%LOG%" 2>&1
    icacls "%DEST_DIR%\DvdScreensaver.scr.old" /reset >> "%LOG%" 2>&1
    ren "%DEST_DIR%\DvdScreensaver.scr.old" "DvdScreensaver.scr.old.removing" >> "%LOG%" 2>&1
)
if exist "%DEST_DIR%\DvdScreensaver.scr.old.removing" (
    del /F /Q "%DEST_DIR%\DvdScreensaver.scr.old.removing" >> "%LOG%" 2>&1
)

echo [5/6] Final state...
if exist "%DEST%" (
    echo.
    echo WARNING: %DEST% is STILL there. Most likely an antivirus
    echo or Windows Search Indexer is holding an open handle. The
    echo file is now scheduled for deletion on the NEXT REBOOT.
    echo.
    powershell -NoProfile -Command "$dst = '%DEST%'; $pending = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'; $cur = (Get-ItemProperty -Path $pending -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations; if ($null -eq $cur) { $cur = @() } else { $cur = @($cur) }; $cur += @(\"`??\\$($dst -replace '/','\\')`\", '`??\\DvdScreensaver.scr.pending\`'); New-ItemProperty -Path $pending -Name PendingFileRenameOperations -Value $cur -PropertyType MultiString -Force | Out-Null" >> "%LOG%" 2>&1
) else (
    echo SUCCESS: %DEST% removed.
)

if exist "%DEST_DIR%\DvdScreensaver.scr.old" (
    echo NOTE: %DEST_DIR%\DvdScreensaver.scr.old is still there, scheduled for deletion on reboot.
    powershell -NoProfile -Command "$dst = '%DEST_DIR%\DvdScreensaver.scr.old'; $pending = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'; $cur = (Get-ItemProperty -Path $pending -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations; if ($null -eq $cur) { $cur = @() } else { $cur = @($cur) }; $cur += @(\"`??\\$($dst -replace '/','\\')`\", '`??\\DvdScreensaver.scr.old.pending\`'); New-ItemProperty -Path $pending -Name PendingFileRenameOperations -Value $cur -PropertyType MultiString -Force | Out-Null" >> "%LOG%" 2>&1
)

echo.
echo [6/6] Done.
echo.
echo Log: %LOG%
echo.
echo If files are still scheduled for deletion, REBOOT your computer
echo to finish the cleanup. After reboot you can re-run install.bat
echo to put the screensaver back if you want.
pause
endlocal
