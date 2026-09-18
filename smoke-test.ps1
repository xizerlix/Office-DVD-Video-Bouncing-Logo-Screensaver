Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;

public static class WinEnum {
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    public static List<string> FindByPid(uint pid) {
        var result = new List<string>();
        EnumWindows((h, l) => {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p == pid && IsWindowVisible(h)) {
                var sb = new StringBuilder(256);
                GetWindowText(h, sb, 256);
                result.Add(string.Format("hwnd=0x{0:X} title='{1}'", h.ToInt64(), sb.ToString()));
            }
            return true;
        }, IntPtr.Zero);
        return result;
    }
}
"@

$exe = "D:\Projects\office_screensaver\bin\DvdScreensaver.exe"
Write-Host "Launching $exe /w ..."
$proc = Start-Process -FilePath $exe -ArgumentList "/w" -PassThru
Start-Sleep -Milliseconds 1500

if ($proc.HasExited) {
    Write-Host "FAIL: process exited immediately with code $($proc.ExitCode)"
    exit 1
}

Write-Host "Process is running: PID=$($proc.Id)"
Write-Host "Visible windows owned by PID:"
[WinEnum]::FindByPid([uint32]$proc.Id) | ForEach-Object { Write-Host "  $_" }

Write-Host "Sending WM_CLOSE to all top-level windows of PID..."
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class WinMsg {
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    public static void CloseByPid(uint pid) {
        EnumWindows((h, l) => {
            uint p; WinEnum.GetWindowThreadProcessId(h, out p);
            if (p == pid) PostMessage(h, 0x0010, IntPtr.Zero, IntPtr.Zero); // WM_CLOSE
            return true;
        }, IntPtr.Zero);
    }
}
"@
[WinMsg]::CloseByPid([uint32]$proc.Id)
Start-Sleep -Milliseconds 800
if (-not $proc.HasExited) {
    Write-Host "Process did not exit on WM_CLOSE; killing..."
    $proc | Stop-Process -Force
}
Write-Host "DONE."
