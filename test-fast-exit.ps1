Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$exe = "D:\Projects\office_screensaver\bin\DvdScreensaver.exe"
if (-not (Test-Path $exe)) {
    Write-Host "FAIL: $exe missing -- run build.bat first"
    exit 1
}

# Start the screensaver in windowed test mode (Bounds.Width >= 320, so the
# fast-exit path is taken when activity is detected).
$proc = Start-Process -FilePath $exe -ArgumentList "/w" -PassThru
Start-Sleep -Milliseconds 1500
if ($proc.HasExited) {
    Write-Host "FAIL: process exited immediately (code=$($proc.ExitCode))"
    exit 1
}
$procId = $proc.Id
Write-Host "Launched PID=$procId"

# Let the form position itself in the centre of the primary monitor, then
# click directly into it.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class W {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, IntPtr extra);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT p);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;

    public static IntPtr FindVisibleByPid(uint pid) {
        IntPtr found = IntPtr.Zero;
        int bestArea = 0;
        EnumWindows((h, l) => {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p == pid) {
                RECT r; GetWindowRect(h, out r);
                int area = (r.Right - r.Left) * (r.Bottom - r.Top);
                if (area > bestArea) { bestArea = area; found = h; }
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc proc, IntPtr lParam);
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
}
"@

$hwnd = [W]::FindVisibleByPid([uint32]$procId)
if ($hwnd -eq [IntPtr]::Zero) {
    Write-Host "FAIL: could not find visible window for PID $procId"
    $proc | Stop-Process -Force
    exit 1
}

$rect = New-Object W+RECT
[W]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
$cx = [int](($rect.Left + $rect.Right) / 2)
$cy = [int](($rect.Top + $rect.Bottom) / 2)
Write-Host "Window center: ($cx, $cy). Clicking..."

[W]::SetCursorPos($cx, $cy) | Out-Null
[W]::mouse_event([W]::MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [IntPtr]::Zero)
[W]::mouse_event([W]::MOUSEEVENTF_LEFTUP, 0, 0, 0, [IntPtr]::Zero)

# Wait up to 2 seconds for the process to terminate on its own.
$exited = $false
$elapsed = 0
for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 50
    $elapsed = ($i + 1) * 50
    if ($proc.HasExited) {
        $exited = $true
        break
    }
}

if ($exited) {
    Write-Host "PASS: process exited in ~${elapsed}ms after click (ExitFast path)"
    exit 0
} else {
    Write-Host "FAIL: process still alive ${elapsed}ms after click"
    Get-CimInstance Win32_Process -Filter "ProcessId=$procId" | ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate }
    exit 1
}
