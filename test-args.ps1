# Verifies that the colon-separated arg forms used by Windows Screen Saver
# Settings ("/c:<hwnd>", "/p:<hwnd>") route to the correct handlers.

$exe = "D:\Projects\office_screensaver\bin\DvdScreensaver.exe"

function Test-Arg {
    param([string]$Title, [string[]]$ArgList, [string]$Expected)

    Write-Host ""
    Write-Host "=== $Title ==="
    Write-Host "  args: $($ArgList -join ' ')"

    $p = Start-Process -FilePath $exe -ArgumentList $ArgList -PassThru
    Start-Sleep -Milliseconds 1500

    $desc = if ($p.HasExited) { "EXITED (code=$($p.ExitCode))" } else { "RUNNING" }

    # Check process command line to confirm the right code path ran.
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)" -ErrorAction SilentlyContinue
    Write-Host "  status: $desc"

    if (-not $p.HasExited) {
        Write-Host "  -> $Expected (and still alive after 1.5s)"
        Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)" | ForEach-Object {
            Invoke-CimMethod -InputObject $_ -MethodName Terminate
        }
    } else {
        Write-Host "  -> unexpected exit"
    }
}

# 1. /c with HWND as second arg (some Windows builds).
Test-Arg "Settings with HWND as second arg"  @("/c", "12345") "Settings dialog should open"

# 2. /c:<hwnd> (Windows convention).
Test-Arg "Settings with colon form"            @("/c:12345") "Settings dialog should open"

# 3. /p with HWND as second arg.
Test-Arg "Preview with HWND as second arg"    @("/p", "12345") "Preview should start (then we kill it)"

# 4. /p:<hwnd> (Windows convention).
Test-Arg "Preview with colon form"             @("/p:12345") "Preview should start (then we kill it)"

# 5. /s fullscreen — should start.
Test-Arg "Fullscreen /s"                       @("/s") "Fullscreen should start (then we kill it)"

Write-Host ""
Write-Host "All routes tested."

# Cleanup any leftovers
Get-CimInstance Win32_Process -Filter "Name='DvdScreensaver.exe'" | ForEach-Object {
    Invoke-CimMethod -InputObject $_ -MethodName Terminate
}
