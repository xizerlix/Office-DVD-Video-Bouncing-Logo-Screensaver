Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Win32 helpers — kept lambda-free so PowerShell here-string parsing is happy.
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;

public static class W {
    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc proc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumProc proc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int n);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);

    public const int GWL_STYLE = -16;
    public const int WS_CHILD = unchecked((int)0x40000000);
    public const int WS_POPUP  = unchecked((int)0x80000000);

    public class WinInfo {
        public IntPtr Hwnd;
        public uint Pid;
        public IntPtr Parent;
        public int Style;
        public bool Visible;
        public string Title;
    }

    // Top-level windows of a given PID.
    public static List<WinInfo> Snapshot(uint targetPid) {
        var list = new List<WinInfo>();
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            uint pid;
            GetWindowThreadProcessId(h, out pid);
            if (pid == targetPid) {
                var sb = new StringBuilder(256);
                GetWindowText(h, sb, 256);
                list.Add(new WinInfo {
                    Hwnd = h, Pid = pid, Parent = GetParent(h),
                    Style = GetWindowLong(h, GWL_STYLE),
                    Visible = IsWindowVisible(h),
                    Title = sb.ToString()
                });
            }
            return true;
        }, IntPtr.Zero);
        return list;
    }

    // Child windows of a given parent HWND that belong to the given PID.
    public static List<WinInfo> SnapshotChildren(IntPtr parent, uint targetPid) {
        var list = new List<WinInfo>();
        EnumChildWindows(parent, delegate(IntPtr h, IntPtr l) {
            uint pid;
            GetWindowThreadProcessId(h, out pid);
            if (pid == targetPid) {
                var sb = new StringBuilder(256);
                GetWindowText(h, sb, 256);
                list.Add(new WinInfo {
                    Hwnd = h, Pid = pid, Parent = GetParent(h),
                    Style = GetWindowLong(h, GWL_STYLE),
                    Visible = IsWindowVisible(h),
                    Title = sb.ToString()
                });
            }
            return true;
        }, IntPtr.Zero);
        return list;
    }
}
"@

# 1. Create a magenta host to act as the "preview pane" parent.
$hostForm = New-Object System.Windows.Forms.Form
$hostForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$hostForm.BackColor = [System.Drawing.Color]::Magenta
$hostForm.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$hostForm.Location = New-Object System.Drawing.Point(0, 0)
$hostForm.Size = New-Object System.Drawing.Size(320, 240)
$hostForm.Text = "PREVIEW-HOST"
$hostForm.TopMost = $true
$null = $hostForm.Show()
[System.Windows.Forms.Application]::DoEvents()
Start-Sleep -Milliseconds 300

$parentHwnd = $hostForm.Handle
$parentHwndHex = "0x$([Convert]::ToString($parentHwnd.ToInt64(), 16))"
Write-Host "Host window: hwnd=$parentHwndHex size=320x240"

# 2. Launch the screensaver in /p mode.
$exe = "D:\Projects\office_screensaver\bin\DvdScreensaver.exe"
$argList = "/p", $parentHwnd.ToInt64().ToString()
$proc = Start-Process -FilePath $exe -ArgumentList $argList -PassThru
Write-Host "Launched PID=$($proc.Id)"
Start-Sleep -Milliseconds 1500

if ($proc.HasExited) {
    Write-Host "FAIL: process exited immediately (code=$($proc.ExitCode))"
    $hostForm.Close()
    exit 1
}
Write-Host "PASS: process alive after 1.5s"

# 3. Enumerate windows owned by our PID.
$snap = [W]::Snapshot([uint32]$proc.Id)
Write-Host "Top-level windows owned by screensaver PID:"
foreach ($w in $snap) {
    $styleHex = "0x$([Convert]::ToString($w.Style, 16))"
    Write-Host ("  hwnd=0x{0:X} parent=0x{1:X} style={2} visible={3} title='{4}'" -f $w.Hwnd.ToInt64(), $w.Parent.ToInt64(), $styleHex, $w.Visible, $w.Title)
}

# 4. Check that screensaver created a CHILD window inside the host pane.
$childSnap = [W]::SnapshotChildren($parentHwnd, [uint32]$proc.Id)
Write-Host "Children of host owned by screensaver PID:"
foreach ($w in $childSnap) {
    $styleHex = "0x$([Convert]::ToString($w.Style, 16))"
    Write-Host ("  hwnd=0x{0:X} parent=0x{1:X} style={2} visible={3} title='{4}'" -f $w.Hwnd.ToInt64(), $w.Parent.ToInt64(), $styleHex, $w.Visible, $w.Title)
}

$childOk = $false
foreach ($w in $childSnap) {
    if (($w.Style -band [W]::WS_CHILD) -ne 0) {
        Write-Host "PASS: screensaver embedded itself as a WS_CHILD inside the host"
        $childOk = $true
    } else {
        Write-Host "FAIL: window inside host is not WS_CHILD"
    }
}
if (-not $childOk) {
    Write-Host "FAIL: no child window of host owned by screensaver (or none has WS_CHILD)"
    $proc | Stop-Process -Force
    $hostForm.Close()
    exit 1
}

# 5. Move mouse over the host — preview must NOT close on mouse activity.
Write-Host "Moving mouse over host..."
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(50, 50)
Start-Sleep -Milliseconds 800
if ($proc.HasExited) { Write-Host "FAIL: preview closed on mouse move"; $hostForm.Close(); exit 1 }
Write-Host "PASS: alive after mouse move"

# 6. Click inside host — preview must NOT close on click.
Write-Host "Sending mouse click..."
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Clicker {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, IntPtr extra);
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
    public static void Click(int x, int y) { SetCursorPos(x, y); mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, IntPtr.Zero); mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, IntPtr.Zero); }
}
"@
[Clicker]::Click(100, 100)
Start-Sleep -Milliseconds 800
if ($proc.HasExited) { Write-Host "FAIL: preview closed on click"; $hostForm.Close(); exit 1 }
Write-Host "PASS: alive after click"

# 7. Send a keystroke — preview must NOT close.
Write-Host "Sending keystroke..."
[System.Windows.Forms.SendKeys]::SendWait(" ")
Start-Sleep -Milliseconds 800
if ($proc.HasExited) { Write-Host "FAIL: preview closed on keypress"; $hostForm.Close(); exit 1 }
Write-Host "PASS: alive after keypress"

Write-Host ""
Write-Host "All checks PASSED. Cleaning up..."
$proc | Stop-Process -Force
$hostForm.Close()
Write-Host "Done."
