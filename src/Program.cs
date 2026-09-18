using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace DvdScreensaver
{
    internal static class Program
    {
        [DllImport("user32.dll")]
        private static extern bool SystemParametersInfo(uint uiAction, uint uiParam, IntPtr pvParam, uint fWinIni);

        private const uint SPI_SETSCREENSAVEACTIVE = 0x0011;

        [STAThread]
        private static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            // Ignore DPI scaling so the screensaver always fills every monitor pixel-perfect.
            if (Environment.OSVersion.Version.Major >= 6)
            {
                SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
            }

            // Parse the argument. Windows can pass either:
            //   "/s", "/p <hwnd>", "/c <hwnd>"
            // or the older colon-separated form:
            //   "/s", "/p:<hwnd>", "/c:<hwnd>"
            //
            // We have to handle both — if we only check args[0] == "/c",
            // the colon form "/c:12345" silently falls through to /s and the
            // user sees the screensaver go fullscreen when they clicked
            // "Settings..." in the picker.
            string mode = "/s";
            IntPtr argHwnd = IntPtr.Zero;
            if (args.Length > 0)
            {
                string raw = args[0].ToLowerInvariant();
                int colon = raw.IndexOf(':');
                if (colon >= 0)
                {
                    mode = raw.Substring(0, colon);
                    long parsed;
                    if (long.TryParse(raw.Substring(colon + 1), out parsed))
                        argHwnd = new IntPtr(parsed);
                }
                else
                {
                    mode = raw;
                }
            }
            if (args.Length >= 2 && argHwnd == IntPtr.Zero)
            {
                argHwnd = new IntPtr(Convert.ToInt32(args[1]));
            }

            try
            {
                if (mode == "/c" || mode == "-c")
                {
                    // Settings... — show the configuration dialog. The HWND
                    // Windows passed (if any) is the Settings dialog's parent;
                    // we ignore it and let our own dialog float on its own.
                    ShowConfigDialog();
                    return;
                }

                if (mode == "/p" || mode == "-p")
                {
                    // Preview — embed into the pane HWND Windows handed us.
                    if (argHwnd == IntPtr.Zero) return;
                    using (var preview = new ScreensaverForm(argHwnd))
                    {
                        // 1) Force the HWND to exist (without showing yet) so
                        //    we can re-style and reparent it synchronously.
                        preview.CreateControl();
                        // 2) Strip top-level styles and adopt our parent.
                        preview.EmbedInPreview();
                        // 3) Only now make it visible — as a proper child of
                        //    the preview pane, with no top-level flash.
                        preview.Show();
                        Application.Run();
                    }
                    return;
                }

                if (mode == "/w" || mode == "-w" || mode == "/test" || mode == "-test")
                {
                    // Windowed test mode — run in a resizable window on the primary
                    // monitor so you can see the screensaver without taking over the
                    // whole desktop. Click or press any key to close.
                    Application.Run(new ScreensaverForm(820, 620, windowed: true));
                    return;
                }

                // Default: /s — full screen on every monitor.
                var screens = Screen.AllScreens;
                var forms = new List<ScreensaverForm>();
                foreach (var screen in screens)
                {
                    var f = new ScreensaverForm(screen);
                    f.Show();
                    forms.Add(f);
                }

                // Make sure Windows still thinks a screensaver is running.
                SystemParametersInfo(SPI_SETSCREENSAVEACTIVE, 1, IntPtr.Zero, 0);

                Application.Run();
            }
            catch (Exception ex)
            {
                MessageBox.Show("DVD Screensaver crashed: " + ex.Message,
                    "DVD Screensaver", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        [DllImport("user32.dll")]
        private static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);
        private static readonly IntPtr DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = new IntPtr(-4);

        private static void ShowConfigDialog()
        {
            // /c — the user clicked "Settings..." in the Screen Saver Settings
            // dialog. Load the persisted settings, show our config dialog, and
            // save on OK.
            var settings = ScreensaverSettings.Load();
            using (var dialog = new SettingsDialog(settings))
            {
                dialog.ShowDialog();
            }
        }
    }

    // -------------------------------------------------------------------------
    //  Persisted user settings (stored in HKCU\Software\TheOfficeScreensaver).
    // -------------------------------------------------------------------------
    public class ScreensaverSettings
    {
        public float SpeedMultiplier = 1.0f;   // 0.5x .. 3.0x
        public float SizeFraction = 0.13f;     // 0.05 .. 0.30 (fraction of screen height)
        public bool ShowDebugText = true;
        public string CornerText = "CORNER!";

        private const string KeyPath = @"Software\TheOfficeScreensaver";

        public static ScreensaverSettings Load()
        {
            var s = new ScreensaverSettings();
            try
            {
                using (var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(KeyPath))
                {
                    if (key == null) return s;
                    var speed = key.GetValue("SpeedMultiplier") as int?;
                    if (speed.HasValue) s.SpeedMultiplier = Math.Max(0.5f, Math.Min(3.0f, speed.Value / 100f));
                    var size = key.GetValue("SizeFraction") as int?;
                    if (size.HasValue) s.SizeFraction = Math.Max(0.05f, Math.Min(0.30f, size.Value / 1000f));
                    var show = key.GetValue("ShowDebugText") as int?;
                    if (show.HasValue) s.ShowDebugText = show.Value != 0;
                    var text = key.GetValue("CornerText") as string;
                    if (!string.IsNullOrEmpty(text)) s.CornerText = text;
                }
            }
            catch { /* fall back to defaults */ }
            return s;
        }

        public void Save()
        {
            try
            {
                using (var key = Microsoft.Win32.Registry.CurrentUser.CreateSubKey(KeyPath))
                {
                    key.SetValue("SpeedMultiplier", (int)Math.Round(SpeedMultiplier * 100f));
                    key.SetValue("SizeFraction", (int)Math.Round(SizeFraction * 1000f));
                    key.SetValue("ShowDebugText", ShowDebugText ? 1 : 0);
                    key.SetValue("CornerText", CornerText ?? "CORNER!");
                }
            }
            catch { /* best effort */ }
        }
    }

    // -------------------------------------------------------------------------
    //  Settings dialog — opened when Windows runs us with /c (the "Settings..."
    //  button in the Screen Saver Settings panel).
    // -------------------------------------------------------------------------
    public class SettingsDialog : Form
    {
        private readonly ScreensaverSettings settings;

        private NumericUpDown speedNud;
        private NumericUpDown sizeNud;
        private CheckBox showDebugCheck;
        private TextBox cornerTextBox;

        public SettingsDialog(ScreensaverSettings settings)
        {
            this.settings = settings;

            Text = "DVD Bouncing Logo Screensaver — Settings";
            FormBorderStyle = FormBorderStyle.FixedDialog;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(440, 320);
            MaximizeBox = false;
            MinimizeBox = false;
            Font = new Font("Segoe UI", 9f);

            int y = 16;

            // Speed
            speedNud = new NumericUpDown
            {
                Left = 150,
                Top = y - 3,
                Width = 70,
                Minimum = 5,
                Maximum = 30,
                Value = (decimal)Math.Round((double)settings.SpeedMultiplier * 10.0),
                Increment = 1
            };
            Controls.Add(new Label { Text = "Speed:", Left = 16, Top = y, Width = 130 });
            Controls.Add(speedNud);
            Controls.Add(new Label
            {
                Text = "0.5x — 3.0x   (default 1.0x)",
                Left = 230,
                Top = y,
                Width = 200,
                ForeColor = SystemColors.GrayText
            });
            y += 36;

            // Size
            sizeNud = new NumericUpDown
            {
                Left = 150,
                Top = y - 3,
                Width = 70,
                Minimum = 5,
                Maximum = 30,
                Value = (decimal)Math.Round((double)settings.SizeFraction * 100.0),
                Increment = 1
            };
            Controls.Add(new Label { Text = "Logo size:", Left = 16, Top = y, Width = 130 });
            Controls.Add(sizeNud);
            Controls.Add(new Label
            {
                Text = "5% — 30% of screen height   (default 13%)",
                Left = 230,
                Top = y,
                Width = 200,
                ForeColor = SystemColors.GrayText
            });
            y += 36;

            // Show debug
            showDebugCheck = new CheckBox
            {
                Text = "Show hit counter in the corner",
                Left = 16,
                Top = y,
                Width = 400,
                Checked = settings.ShowDebugText
            };
            Controls.Add(showDebugCheck);
            y += 36;

            // Corner text
            Controls.Add(new Label
            {
                Text = "Corner-hit celebration text:",
                Left = 16,
                Top = y,
                Width = 400
            });
            y += 22;

            cornerTextBox = new TextBox
            {
                Left = 16,
                Top = y,
                Width = 408,
                Text = settings.CornerText
            };
            Controls.Add(cornerTextBox);
            y += 44;

            // Buttons — Defaults on the left, OK / Cancel on the right.
            var defaultsButton = new Button
            {
                Text = "Defaults",
                Left = 16,
                Top = y,
                Width = 80
            };
            defaultsButton.Click += (s, e) =>
            {
                speedNud.Value = 10;       // 1.0x
                sizeNud.Value = 13;        // 13%
                showDebugCheck.Checked = true;
                cornerTextBox.Text = "CORNER!";
            };
            Controls.Add(defaultsButton);

            var okButton = new Button
            {
                Text = "OK",
                Left = 256,
                Top = y,
                Width = 80,
                DialogResult = DialogResult.OK
            };
            var cancelButton = new Button
            {
                Text = "Cancel",
                Left = 344,
                Top = y,
                Width = 80,
                DialogResult = DialogResult.Cancel
            };
            Controls.Add(okButton);
            Controls.Add(cancelButton);

            AcceptButton = okButton;
            CancelButton = cancelButton;
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (DialogResult == DialogResult.OK)
            {
                settings.SpeedMultiplier = (float)((double)speedNud.Value / 10.0);
                settings.SizeFraction = (float)((double)sizeNud.Value / 100.0);
                settings.ShowDebugText = showDebugCheck.Checked;
                settings.CornerText = string.IsNullOrWhiteSpace(cornerTextBox.Text)
                    ? "CORNER!"
                    : cornerTextBox.Text;
                settings.Save();
            }
            base.OnFormClosing(e);
        }
    }

    // -------------------------------------------------------------------------
    //  The screensaver form. One instance per monitor in fullscreen mode.
    // -------------------------------------------------------------------------
    public class ScreensaverForm : Form
    {
        // P/Invoke for cursor hiding and keyboard/mouse activity detection.
        [DllImport("user32.dll")]
        private static extern bool GetCursorPos(out POINT lpPoint);

        [DllImport("user32.dll")]
        private static extern int ShowCursor(bool bShow);

        [DllImport("user32.dll")]
        private static extern short GetAsyncKeyState(int vKey);

        [StructLayout(LayoutKind.Sequential)]
        private struct POINT { public int X; public int Y; }

        // P/Invoke for the Windows screensaver preview path: we have to embed
        // our form as a CHILD of the static control that the Screen Saver
        // Settings dialog hands us, otherwise the preview shows as a stray
        // top-level window in the corner of the screen instead of inside the
        // preview pane.
        [DllImport("user32.dll")]
        private static extern IntPtr SetParent(IntPtr hWndChild, IntPtr hWndNewParent);

        [DllImport("user32.dll")]
        private static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
            int X, int Y, int cx, int cy, uint uFlags);

        [DllImport("user32.dll")]
        private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll")]
        private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

        [StructLayout(LayoutKind.Sequential)]
        private struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

        private const int GWL_STYLE = -16;

        // Window styles. WS_POPUP and WS_CHILD are mutually exclusive for
        // embedding — a WS_POPUP window can't be SetParent'd into another
        // window properly, which is what was making the preview appear as a
        // stray top-level window in the corner of the screen.
        private const int WS_CHILD        = unchecked((int)0x40000000);
        private const int WS_VISIBLE      = 0x10000000;
        private const int WS_CLIPSIBLINGS = 0x04000000;
        private const int WS_CLIPCHILDREN = 0x02000000;
        private const int WS_POPUP        = unchecked((int)0x80000000);
        private const int WS_CAPTION      = 0x00C00000; // WS_BORDER | WS_DLGFRAME
        private const int WS_BORDER       = 0x00800000;
        private const int WS_DLGFRAME     = 0x00400000;
        private const int WS_SYSMENU      = 0x00080000;
        private const int WS_THICKFRAME   = 0x00040000;

        private const uint SWP_NOZORDER = 0x0004;
        private const uint SWP_NOACTIVATE = 0x0010;
        private const uint SWP_FRAMECHANGED = 0x0020;

        // VK codes we treat as "user wants out".
        private const int VK_LBUTTON = 0x01;
        private const int VK_RBUTTON = 0x02;
        private const int VK_MBUTTON = 0x04;
        private const int VK_ESCAPE = 0x1B;
        private const int VK_SPACE = 0x20;
        private const int VK_RETURN = 0x0D;

        private readonly Random rng = new Random();
        private readonly Timer timer = new Timer();

        // Animation state.
        private float x;
        private float y;
        private float vx;
        private float vy;
        private float cornerFlash;     // 0..1 — pulses on a perfect corner hit
        private int hits;              // number of wall hits
        private int cornerHits;       // number of perfect corner hits
        private string lastCornerName; // which corner we last landed in

        // Mouse tracking. We record where the cursor is when the screensaver
        // starts and only treat movement as "exit" if the cursor moved more than
        // a small slack from that initial position. This is how Windows'
        // built-in screensavers detect activity and stops the form from closing
        // the instant Windows fires a phantom WM_MOUSEMOVE on first show.
        private static readonly int MouseSlackPx = 12;
        private POINT startMousePos;
        private bool startMouseRecorded;

        // True when this form is embedded inside the Screen Saver Settings
        // preview pane. In that mode we MUST NOT close on mouse/keyboard
        // activity — Windows closes us when the user clicks Apply/OK or
        // selects another screensaver.
        private bool isPreview;

        // User-tweakable runtime settings (loaded from HKCU in each
        // constructor so changes from the Settings dialog take effect the
        // next time the screensaver launches).
        private float speedMultiplier = 1.0f;
        private bool showDebugText = true;
        private string cornerText = "CORNER!";

        // Logo geometry.
        // The original DVD Video logo is roughly square — width equals height.
        private const float LogoAspect = 1.0f; // width / height
        // Default logo size — used when no Settings have been saved yet. The
        // actual value at runtime comes from ScreensaverSettings.SizeFraction.
        private const float DefaultSizeFraction = 0.13f;
        private float sizeFraction = DefaultSizeFraction;
        private float logoHeight;
        private float logoWidth;

        // Body color palette — saturated fills under BLACK "DVD" and WHITE "VIDEO".
        // White and near-black are excluded so the mark stays visible.
        private static readonly Color[] Palette = new Color[]
        {
            Color.FromArgb(220, 30, 30),    // classic DVD red
            Color.FromArgb(255, 200, 0),    // gold
            Color.FromArgb(255, 140, 0),    // orange
            Color.FromArgb(230, 90, 200),   // pink / magenta
            Color.FromArgb(80, 200, 255),   // sky blue
            Color.FromArgb(120, 220, 90),   // light green
        };
        private int colorIndex;

        public ScreensaverForm()
            : this(Screen.PrimaryScreen) { }

        public ScreensaverForm(Screen target)
        {
            FormBorderStyle = FormBorderStyle.None;
            WindowState = FormWindowState.Normal;
            StartPosition = FormStartPosition.Manual;
            Bounds = target.Bounds;
            TopMost = true;
            ShowInTaskbar = false;
            Cursor = Cursors.Default;
            BackColor = Color.Black;
            DoubleBuffered = true;
            KeyPreview = true;

            // Apply user-tweakable settings (speed, logo size, debug text, corner text).
            ApplySettings();

            // Random initial position (not stuck in a corner at start).
            x = rng.Next(0, Math.Max(1, Bounds.Width - (int)logoWidth));
            y = rng.Next(0, Math.Max(1, Bounds.Height - (int)logoHeight));

            // Velocity: about 18% of screen height per second horizontally,
            // a touch slower vertically so the diagonal feels right.
            float baseSpeed = Math.Max(120f, Bounds.Height * 0.18f) * speedMultiplier;
            vx = (rng.Next(0, 2) == 0 ? -1f : 1f) * baseSpeed;
            vy = (rng.Next(0, 2) == 0 ? -1f : 1f) * baseSpeed * 0.75f;

            colorIndex = rng.Next(Palette.Length);

            timer.Interval = 16; // ~60 FPS
            timer.Tick += Tick;
            timer.Start();

            Shown += OnFirstShown;
            FormClosed += (s, e) =>
            {
                while (ShowCursor(true) < 0) { /* restore cursor refcount */ }
                timer.Stop();
            };

            // Keyboard: any key closes — but only once the form is actually shown,
            // not during the first paint.
            KeyDown += OnKeyDown;
            // Mouse click closes immediately. Mouse *move* is handled via polling
            // inside Tick, because binding MouseMove closes the form on phantom
            // events Windows sends the moment a fullscreen window appears.
            MouseDown += OnMouseDown;
        }

        // Windowed test mode — runs in a resizable window so you can verify the
        // animation without taking over the whole desktop.
        public ScreensaverForm(int width, int height, bool windowed)
        {
            FormBorderStyle = FormBorderStyle.Sizable;
            WindowState = FormWindowState.Normal;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(width, height);
            Text = "DVD Screensaver — test mode  (click or press any key to close)";
            BackColor = Color.Black;
            DoubleBuffered = true;
            KeyPreview = true;
            MaximizeBox = true;
            MinimizeBox = true;

            ApplySettings();

            x = 40; y = 40;
            float speed = 180f * speedMultiplier;
            vx = speed; vy = speed * 0.75f;

            colorIndex = rng.Next(Palette.Length);

            timer.Interval = 16;
            timer.Tick += Tick;
            timer.Start();

            KeyDown += OnKeyDown;
            MouseDown += OnMouseDown;
        }

        // Saved preview pane HWND — set in the preview constructor and used
        // by EmbedInPreview() called from Program.Main *before* Show().
        private IntPtr previewParentHandle;

        // Cached size of the preview pane so we can resize after reparenting
        // without re-querying the parent.
        private int previewPaneWidth;
        private int previewPaneHeight;

        public ScreensaverForm(IntPtr previewHandle)
        {
            isPreview = true;
            previewParentHandle = previewHandle;

            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            BackColor = Color.Black;
            DoubleBuffered = true;
            ShowInTaskbar = false;
            KeyPreview = true;

            // Find out how big the preview pane is. Windows passes us a static
            // control that lives inside the Settings dialog; we have to size
            // our form to fit it, otherwise we'd draw outside the preview area.
            RECT rc;
            GetClientRect(previewHandle, out rc);
            previewPaneWidth = Math.Max(60, rc.Right - rc.Left);
            previewPaneHeight = Math.Max(40, rc.Bottom - rc.Top);
            Bounds = new Rectangle(0, 0, previewPaneWidth, previewPaneHeight);

            // Apply user settings (so the preview reflects what the user picked).
            ApplySettings();

            x = previewPaneWidth * 0.15f;
            y = previewPaneHeight * 0.15f;
            float speed = Math.Max(20f, previewPaneHeight * 0.22f) * speedMultiplier;
            vx = speed;
            vy = speed * 0.75f;

            colorIndex = rng.Next(Palette.Length);

            timer.Interval = 33;
            timer.Tick += Tick;
            // Note: timer.Start() is intentionally NOT called here — it runs
            // after EmbedInPreview() so the animation only starts once the
            // form is a proper child of the preview pane.
        }

        /// <summary>
        /// Re-styles our HWND as a child window and reparents it under the
        /// preview pane. Must be called from Program.Main *after* the handle
        /// has been created (e.g. via CreateControl()) and *before* Show().
        /// Doing it this way guarantees the form never flashes as a stray
        /// top-level window in the corner of the screen for a single frame.
        /// </summary>
        public void EmbedInPreview()
        {
            if (!isPreview) return;

            IntPtr hwnd = Handle; // forces handle creation if needed

            // 1) Strip top-level decorations and add WS_CHILD. WinForms gives
            //    a fresh Form WS_POPUP by default — SetParent on such a window
            //    is unreliable, the window keeps acting like a top-level and
            //    the Settings dialog ends up with a stray window in the corner.
            int style = GetWindowLong(hwnd, GWL_STYLE);
            style &= ~(WS_POPUP | WS_CAPTION | WS_BORDER | WS_DLGFRAME |
                       WS_SYSMENU | WS_THICKFRAME);
            style |= (WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | WS_CLIPCHILDREN);
            SetWindowLong(hwnd, GWL_STYLE, style);

            // 2) Reparent into the preview pane.
            SetParent(hwnd, previewParentHandle);

            // 3) Move/resize to fill the preview pane's client area.
            SetWindowPos(hwnd, IntPtr.Zero,
                0, 0, previewPaneWidth, previewPaneHeight,
                SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);

            // 4) Force WinForms to re-read the new HWND size back into its own
            //    Bounds/ClientSize state. Without this the collision code in
            //    Tick() would still see the old (larger) Bounds and the logo
            //    could end up glued to the bottom or top of the visible area.
            //    This was the cause of "logo only moves along the bottom
            //    edge" in tiny previews.
            Bounds = new Rectangle(0, 0, previewPaneWidth, previewPaneHeight);
            ClientSize = new Size(previewPaneWidth, previewPaneHeight);

            // 5) Re-derive logo size and velocity from the *real* client size
            //    so they look right in a 152x112 preview pane as well as in a
            //    1920x1080 fullscreen.
            RecomputeForSize(ClientSize.Width, ClientSize.Height);

            // 6) Now that we're a proper child, start the animation.
            timer.Start();
        }

        /// <summary>
        /// Reads the persisted user settings and applies them to the in-memory
        /// fields used by the animation. Called from every constructor.
        /// </summary>
        private void ApplySettings()
        {
            var settings = ScreensaverSettings.Load();
            speedMultiplier = settings.SpeedMultiplier;
            showDebugText = settings.ShowDebugText;
            cornerText = settings.CornerText;
            sizeFraction = settings.SizeFraction;

            // Set logo size based on the current Bounds (fullscreen / windowed
            // / preview all set Bounds before calling this).
            RecomputeForSize(Bounds.Width, Bounds.Height);
        }

        /// <summary>
        /// Recomputes logo geometry and initial position from a given client
        /// size. Used both at startup (after ApplySettings) and after the
        /// preview pane has been resized by SetWindowPos.
        /// </summary>
        private void RecomputeForSize(int width, int height)
        {
            // Logo: a square that fits comfortably. The minimum keeps it
            // visible even in a 60-px preview pane, but is small enough to
            // not overflow the pane and lock the collision check at one edge.
            logoHeight = Math.Max(6f, Math.Min(height * sizeFraction, height - 4f));
            logoWidth = logoHeight * LogoAspect;

            // If the logo is somehow still bigger than the pane (shouldn't
            // happen, but be defensive), clamp it again.
            if (logoWidth > width - 4f)
            {
                logoWidth = width - 4f;
                logoHeight = logoWidth / LogoAspect;
            }

            // Re-center initial position (only on first setup — Tick
            // overwrites x/y on every frame).
            if (x == 0f && y == 0f)
            {
                x = width * 0.15f;
                y = height * 0.15f;
            }
        }

        private void OnFirstShown(object sender, EventArgs e)
        {
            // Preview mode: do nothing. The form is already parented to the
            // preview pane, must NOT steal focus from the Settings dialog,
            // and must NOT hide the user's cursor.
            if (isPreview) return;

            // Hide the system cursor only after the form is actually visible —
            // doing it during Load() can race with the very first paint.
            while (ShowCursor(false) >= 0) { /* keep hiding */ }

            // Bring the form to the front so the user actually sees it.
            BringToFront();
            Activate();

            // Record the initial mouse position so subsequent small jitter
            // (e.g. from the touchpad settling) does not register as activity.
            POINT p;
            GetCursorPos(out p);
            startMousePos = p;
            startMouseRecorded = true;

            // Force one immediate paint so the screen isn't black for a frame.
            Invalidate();
        }

        private void OnMouseDown(object sender, MouseEventArgs e)
        {
            // Preview mode never reacts to clicks — Windows kills the process
            // when the user picks another screensaver or closes the dialog.
            if (isPreview) return;
            ExitFast();
        }

        private void OnKeyDown(object sender, KeyEventArgs e)
        {
            if (isPreview) return;
            ExitFast();
        }

        /// <summary>
        /// Tear down the screensaver immediately. Windows is waiting for the
        /// process to terminate after activity is detected so it can show the
        /// lock screen — if our process lingers (because of leftover helper
        /// windows or in-flight timers), Windows falls back to a gray
        /// "secure desktop" and the user has to mash Ctrl+Alt+Del. Calling
        /// Environment.Exit() bypasses the WinForms shutdown dance entirely.
        /// </summary>
        private void ExitFast()
        {
            // Restore the cursor refcount we accumulated with ShowCursor(false).
            // We can't wait for FormClosed to do this because we won't reach it
            // — we are about to yank the process out from under the message pump.
            try
            {
                while (ShowCursor(true) < 0) { /* restore cursor */ }
            }
            catch { /* best effort */ }

            // Hard-exit the process synchronously. Going through ThreadPool +
            // Sleep is unreliable because the worker thread can be starved by
            // the message pump we are currently running on, and Windows will
            // time out waiting for us and show the gray secure desktop.
            Environment.Exit(0);
        }

        private void Tick(object sender, EventArgs e)
        {
            float dt = timer.Interval / 1000f;

            // 1) Move.
            x += vx * dt;
            y += vy * dt;

            // 2) Collide with walls. The classic angle-of-incidence behavior:
            //    a hit flips *only* the axis that the wall is on, so the angle
            //    against the wall is preserved — which is what makes the logo
            //    eventually drift toward a corner.
            //
            //    Use ClientSize, not Bounds: ClientSize is the *paint* area,
            //    and it stays consistent regardless of whether the form is
            //    currently a top-level window or has been reparented as a
            //    child of the Settings preview pane via SetWindowPos.
            bool hitWall = false;
            int edgeTolerance = 1;
            int cwidth = ClientSize.Width;
            int cheight = ClientSize.Height;

            if (cwidth <= 0 || cheight <= 0)
            {
                // Form hasn't been sized yet; nothing to bounce off of.
                Invalidate();
                return;
            }

            if (x <= 0)
            {
                x = 0;
                if (vx < 0) { vx = -vx; hitWall = true; }
            }
            else if (x + logoWidth >= cwidth - edgeTolerance)
            {
                x = cwidth - logoWidth;
                if (vx > 0) { vx = -vx; hitWall = true; }
            }

            if (y <= 0)
            {
                y = 0;
                if (vy < 0) { vy = -vy; hitWall = true; }
            }
            else if (y + logoHeight >= cheight - edgeTolerance)
            {
                y = cheight - logoHeight;
                if (vy > 0) { vy = -vy; hitWall = true; }
            }

            if (hitWall)
            {
                hits++;
                // Advance the color, but never pick the same one twice in a row.
                int next;
                do { next = rng.Next(Palette.Length); } while (next == colorIndex);
                colorIndex = next;
            }

            // 3) Corner detection — a "perfect" corner means the logo is touching
            //    two adjacent walls within a few pixels.
            int cornerSlack = 3;
            bool atLeft = x <= cornerSlack;
            bool atRight = (x + logoWidth) >= cwidth - cornerSlack;
            bool atTop = y <= cornerSlack;
            bool atBottom = (y + logoHeight) >= cheight - cornerSlack;

            bool cornerHit = (atLeft || atRight) && (atTop || atBottom);
            if (cornerHit && hits > 1)
            {
                cornerHits++;
                cornerFlash = 1f;
                if (atLeft && atTop) lastCornerName = "TOP-LEFT";
                else if (atRight && atTop) lastCornerName = "TOP-RIGHT";
                else if (atLeft && atBottom) lastCornerName = "BOTTOM-LEFT";
                else lastCornerName = "BOTTOM-RIGHT";
            }

            // 4) Decay the corner flash.
            if (cornerFlash > 0f)
            {
                cornerFlash -= dt * 1.5f;
                if (cornerFlash < 0f) cornerFlash = 0f;
            }

            // 5) Activity detection — exit only on *meaningful* movement. In
            //    preview mode (Settings panel) we never react to mouse motion,
            //    because the user is navigating the dialog, not the screensaver.
            //    Polling GetCursorPos is more reliable than the MouseMove event
            //    here, because that event fires on the very first WM_MOUSEMOVE
            //    Windows sends when a fullscreen form appears, which would close
            //    the screensaver before the user even sees it.
            if (!isPreview && cwidth >= 320 && startMouseRecorded)
            {
                POINT current;
                GetCursorPos(out current);
                int dx = current.X - startMousePos.X;
                int dy = current.Y - startMousePos.Y;
                if (Math.Abs(dx) > MouseSlackPx || Math.Abs(dy) > MouseSlackPx)
                {
                    ExitFast();
                    return;
                }
            }

            Invalidate();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAlias;

            // Black background.
            g.Clear(Color.Black);

            Color bodyColor = Palette[colorIndex];
            // On a perfect corner hit, brighten the whole frame briefly.
            if (cornerFlash > 0f)
            {
                int boost = (int)(cornerFlash * 60);
                bodyColor = Color.FromArgb(
                    255,
                    Math.Min(255, bodyColor.R + boost),
                    Math.Min(255, bodyColor.G + boost),
                    Math.Min(255, bodyColor.B + boost));
            }

            DrawDvdLogo(g, x, y, logoWidth, logoHeight, bodyColor);

            // Subtle hit counter in the corner — toggleable in Settings. We
            // also suppress it in preview mode so the preview pane stays clean.
            if (showDebugText && !isPreview)
            {
                using (var font = new Font("Segoe UI", 9f, FontStyle.Regular))
                using (var brush = new SolidBrush(Color.FromArgb(120, 255, 255, 255)))
                {
                    string line = string.Format("hits: {0}    corner hits: {1}", hits, cornerHits);
                    var size = g.MeasureString(line, font);
                    g.DrawString(line, font, brush, ClientSize.Width - size.Width - 8, 6);
                }
            }

            // Corner-hit celebration overlay — fades out over ~1.5 seconds.
            // The Office moment: when the DVD logo finally hits the corner, you get it.
            if (cornerFlash > 0f)
            {
                int alpha = (int)(cornerFlash * 220);
                using (var font = new Font("Segoe UI Black", Math.Max(28f, ClientSize.Height * 0.07f), FontStyle.Bold, GraphicsUnit.Pixel))
                using (var brush = new SolidBrush(Color.FromArgb(alpha, 255, 255, 255)))
                {
                    string msg = cornerText ?? "CORNER!";
                    var size = g.MeasureString(msg, font);
                    float tx = (ClientSize.Width - size.Width) / 2f;
                    float ty = ClientSize.Height * 0.12f;
                    g.DrawString(msg, font, brush, tx, ty);
                }

                using (var font = new Font("Segoe UI", Math.Max(12f, ClientSize.Height * 0.022f), FontStyle.Regular, GraphicsUnit.Pixel))
                using (var brush = new SolidBrush(Color.FromArgb(alpha, 255, 255, 255)))
                {
                    string sub = string.Format("{0}  —  total corner hits: {1}", lastCornerName, cornerHits);
                    var size = g.MeasureString(sub, font);
                    float tx = (ClientSize.Width - size.Width) / 2f;
                    float ty = ClientSize.Height * 0.12f + Math.Max(40f, ClientSize.Height * 0.09f);
                    g.DrawString(sub, font, brush, tx, ty);
                }
            }
        }

        private static void DrawDvdLogo(Graphics g, float x, float y, float w, float h, Color color)
        {
            using (var shadow = new SolidBrush(Color.FromArgb(90, 0, 0, 0)))
            {
                g.FillRectangle(shadow, x + 3, y + 3, w, h);
            }

            using (var body = new SolidBrush(color))
            {
                g.FillRectangle(body, x, y, w, h);
            }

            // Classic bouncing-DVD mark: sharp square, italic BLACK "DVD"
            // over upright WHITE "VIDEO", both condensed to the same width.
            FontFamily dvdFamily = null;
            FontFamily videoFamily = null;
            try
            {
                dvdFamily = NewFontFamily("Arial Black", "Arial");
                videoFamily = NewFontFamily("Arial", "Segoe UI");

                int dvdStyle = dvdFamily.IsStyleAvailable(FontStyle.Bold)
                    ? (int)FontStyle.Bold : (int)FontStyle.Regular;
                int videoStyle = videoFamily.IsStyleAvailable(FontStyle.Bold)
                    ? (int)FontStyle.Bold : (int)FontStyle.Regular;

                float cx = x + w * 0.5f;
                float wordWidth = w * 0.74f;
                DrawWordmark(g, "DVD", dvdFamily, dvdStyle, h * 0.40f,
                    cx, y + h * 0.412f, wordWidth, -0.36f, Color.FromArgb(12, 12, 12));
                DrawWordmark(g, "VIDEO", videoFamily, videoStyle, h * 0.138f,
                    cx, y + h * 0.682f, wordWidth, 0f, Color.White);
            }
            finally
            {
                if (dvdFamily != null) dvdFamily.Dispose();
                if (videoFamily != null) videoFamily.Dispose();
            }
        }

        private static FontFamily NewFontFamily(string preferred, string fallback)
        {
            try { return new FontFamily(preferred); }
            catch (ArgumentException) { return new FontFamily(fallback); }
        }

        private static void DrawWordmark(Graphics g, string text, FontFamily family, int style,
            float emSize, float cx, float cy, float targetWidth, float shearX, Color color)
        {
            using (var path = new GraphicsPath())
            using (var format = (StringFormat)StringFormat.GenericTypographic.Clone())
            {
                format.Alignment = StringAlignment.Near;
                format.LineAlignment = StringAlignment.Near;
                path.AddString(text, family, style, emSize, PointF.Empty, format);

                RectangleF b = path.GetBounds();
                if (b.Width < 0.5f || b.Height < 0.5f) return;

                using (var toOrigin = new Matrix())
                {
                    toOrigin.Translate(-(b.X + b.Width * 0.5f), -(b.Y + b.Height * 0.5f));
                    path.Transform(toOrigin);
                }

                if (Math.Abs(shearX) > 0.001f)
                {
                    using (var shear = new Matrix())
                    {
                        shear.Shear(shearX, 0f);
                        path.Transform(shear);
                    }
                }

                b = path.GetBounds();
                using (var place = new Matrix())
                {
                    float sx = targetWidth / b.Width;
                    place.Scale(sx, 1f);
                    place.Translate(cx, cy, MatrixOrder.Append);
                    path.Transform(place);
                }

                using (var brush = new SolidBrush(color))
                {
                    g.FillPath(brush, path);
                }
            }
        }
    }
}
