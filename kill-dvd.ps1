$ErrorActionPreference = 'Continue'
$procList = Get-CimInstance Win32_Process -Filter "Name='DvdScreensaver.exe'"
$procIds = @($procList | ForEach-Object { $_.ProcessId })
Write-Host "Found PIDs: $($procIds -join ', ')"

foreach ($procId in $procIds) {
    Write-Host "--- Trying PID $procId ---"

    try {
        $p = Get-CimInstance Win32_Process -Filter "ProcessId=$procId"
        $result = Invoke-CimMethod -InputObject $p -MethodName Terminate
        Write-Host "WMI Terminate result: $($result.ReturnValue)"
    } catch {
        Write-Host "WMI Terminate failed: $_"
    }

    try {
        Stop-Process -Id $procId -Force -ErrorAction Stop
        Write-Host "Stop-Process ok"
    } catch {
        Write-Host "Stop-Process failed: $_"
    }
}

Start-Sleep -Seconds 1
$remaining = Get-Process DvdScreensaver -ErrorAction SilentlyContinue
if ($remaining) {
    Write-Host "STILL RUNNING: $($remaining.Id -join ', ')"
} else {
    Write-Host "All gone."
}
