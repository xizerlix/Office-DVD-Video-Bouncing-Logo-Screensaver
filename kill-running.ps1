# Synchronously kill any process whose executable path matches the pattern.
# Uses TerminateProcess (kernel32) which is reliable even when WMI returns
# success but the OS hasn't actually reaped the process yet — important when
# the Screen Saver Settings dialog is in a tight respawn loop.

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class K {
    [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint a, bool i, uint p);
    [DllImport("kernel32.dll")] public static extern bool TerminateProcess(IntPtr h, uint c);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
    public const uint T = 0x0001;
}
'@

for ($i = 0; $i -lt 10; $i++) {
    $procs = Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -like "*DvdScreensaver*" }
    if (-not $procs) { break }
    foreach ($p in $procs) {
        $h = [K]::OpenProcess([K]::T, $false, [uint32]$p.ProcessId)
        if ($h -ne [IntPtr]::Zero) {
            [K]::TerminateProcess($h, 1) | Out-Null
            [K]::CloseHandle($h) | Out-Null
        }
    }
    Start-Sleep -Milliseconds 400
}

$left = (Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -like "*DvdScreensaver*" }).Count
Write-Host ("kill-running: $left remaining.")
