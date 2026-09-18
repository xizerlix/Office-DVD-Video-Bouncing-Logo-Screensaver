# Aggressive cleaner: disable screensaver spawning, then loop-kill all
# DvdScreensaver processes until none remain.

# 1) Disable the active screensaver so Windows stops spawning the .scr.
reg add "HKCU:\Control Panel\Desktop" /v ScreenSaveActive /d 0 /t REG_SZ /f | Out-Null
Write-Host "ScreenSaveActive set to 0."

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class K {
    [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
    [DllImport("kernel32.dll")] public static extern bool TerminateProcess(IntPtr h, uint code);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
    public const uint PROC_TERMINATE = 0x0001;
}
'@

for ($i = 0; $i -lt 30; $i++) {
    $procs = Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -like "*DvdScreensaver*" }
    if (-not $procs) {
        Write-Host ("Iteration " + $i + ": no processes remaining.")
        break
    }
    foreach ($p in $procs) {
        $h = [K]::OpenProcess([K]::PROC_TERMINATE, $false, [uint32]$p.ProcessId)
        if ($h -ne [IntPtr]::Zero) {
            [K]::TerminateProcess($h, 1) | Out-Null
            [K]::CloseHandle($h) | Out-Null
        }
    }
    Write-Host ("Iteration " + $i + ": killed " + $procs.Count + " process(es).")
    Start-Sleep -Milliseconds 500
}

$rem = Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -like "*DvdScreensaver*" }
Write-Host ("Final: " + $rem.Count + " processes remain.")
if ($rem) { $rem | Format-Table ProcessId, Name, ExecutablePath }
