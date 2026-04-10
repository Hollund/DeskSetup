# DeskSetup

Save and restore your Windows desk setup — multi-display mode and default audio device — with a single click.

No installation required. Pure PowerShell, no third-party dependencies.

---

## What it does

Click **Save Profile 1** (or 2/3/4) in the `SetDesk Profiles` folder to snapshot your current setup. Click **Load Profile 1** to restore it. That's it.

Each profile stores:
- Multi-display mode (Extended / Duplicate / Show Only 1 / Show Only External)
- Default audio output device

It does **not** change resolution or refresh rate.

---

## Folder Structure

```
DeskSetup/
├── Save_Profile.ps1          ← save current setup to a numbered profile
├── Load_Profile.ps1          ← restore a saved profile
├── SetDesk Profiles/         ← shortcuts + saved profile files (json/txt)
│   └── Create-Shortcuts.ps1  ← recreate the Save/Load shortcuts
├── lib/                      ← core logic scripts
│   ├── Get-DeskSetup.ps1
│   ├── Apply-DeskSetup.ps1
│   ├── Get-DisplaySettings.ps1
│   └── Get-SoundSettings.ps1
└── output/                   ← ad-hoc reports (gitignored)
```

---

## Getting started

1. Clone or copy the folder anywhere on your PC
2. Run `SetDesk Profiles\Create-Shortcuts.ps1` once to create the shortcuts
3. Use the shortcuts in `SetDesk Profiles\` to save and load

> If PowerShell blocks the scripts, run once:
> ```powershell
> Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
> ```

---

## Command line usage

```powershell
.\Save_Profile.ps1 -n 1   # save current setup as profile 1
.\Load_Profile.ps1 -n 1   # restore profile 1
```

Optional arguments:

| Argument | Default | Description |
|---|---|---|
| `-n` | required | Profile number (1, 2, 3 ...) |
| `-ProfilesDir` | `SetDesk Profiles\` | Where profiles are stored |
| `-Prefix` | `profile_` | Filename prefix |

---

## Alternatives

If you need more advanced switching (resolution, refresh rate, per-app audio routing):

| Tool | What it adds |
|---|---|
| [DisplayFusion](https://www.displayfusion.com/) | Full multi-monitor management, wallpaper, hotkeys |
| [MonitorSwitcher](https://sourceforge.net/projects/monitorswitcher/) | Save/restore full display layout including resolution |
| [NirSoft MultiMonitorTool](https://www.nirsoft.net/utils/multi_monitor_tool.html) | Command-line display switching, free |
| [SoundSwitch](https://github.com/Belphemur/SoundSwitch) | Hotkey-based audio device switcher, open source |
| [AutoHotkey](https://www.autohotkey.com/) | Script anything, full control |

DeskSetup is intentionally minimal — no GUI, no tray icon, no install. Just shortcuts that work.
| `Get-SoundSettings.ps1` | Default audio device only |

---

## Requirements

- Windows 10 / 11
- PowerShell 5.1 or later (pre-installed on Windows)
- No additional modules required
