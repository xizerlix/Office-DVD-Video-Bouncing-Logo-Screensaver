# Office DVD Screensaver

The bouncing DVD-logo screensaver from the TV series *The Office*
(Season 4, Episode 5 — "Job Fair"). The employees of Dunder Mifflin
sit in a conference room and stare at the bouncing square, waiting
for it to hit the corner.

![The Office — DVD screensaver scene](docs/show.gif)

![My screensaver running](docs/screensaver.gif)

## Install

### From a release (most users)

1. Download `DvdScreensaver-vX.Y.Z.zip` from the
   [Releases page](../../releases) page.
2. Unzip it anywhere.
3. Right-click `install.bat` → **Run as administrator**.

The installer copies the binary to `C:\Windows\System32\DvdScreensaver.scr`,
registers it with Windows, and sets it as your active screensaver.

### Manual install (just the binary)

1. Download `DvdScreensaver.scr` from the
   [Releases page](../../releases) page.
2. Drop it into `C:\Windows\System32\`.
3. Open **Settings → Personalization → Lock screen → Screen saver
   settings** and pick **DVD Bouncing Logo (The Office Edition)**
   from the dropdown.

## Customize

Click **Settings...** in the Screen Saver settings panel to open the
configuration dialog:

| Control | Range | Default |
|---|---|---|
| Speed | 0.5× – 3.0× | 1.0× |
| Logo size | 5% – 30% of screen height | 13% |
| Show hit counter | toggle | on |
| Corner text | string | `CORNER!` |

The **Defaults** button restores all four to their original values.

Settings are stored in `HKCU\Software\TheOfficeScreensaver`.

## Uninstall

Right-click `uninstall.bat` → **Run as administrator**. Removes the
screensaver from `System32` and cleans up registry entries.

## Build from source

Requires .NET Framework 4.x (preinstalled on every Windows 7+ system,
including Windows 11). Just run `build.bat` — it calls `csc.exe`
directly, no Visual Studio or .NET SDK needed.

## License

MIT — see [LICENSE](LICENSE).
