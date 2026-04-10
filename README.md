# DeskSetup

A PowerShell tool that snapshots your current Windows display layout and audio device to a text file.

---

## Main Script

### `Get-DeskSetup.ps1`

Saves a combined display + audio report to a text file.

**What it captures:**
- Multi-display mode (Extended / Duplicate / Show Only 1 / Show Only External)
- Active monitors — name, refresh rate, and which one is the main display
- Default audio output device

**How to run:**

```powershell
cd "path\to\DeskSetup"

# Save with a timestamp
.\Get-DeskSetup.ps1

# Save with a custom name
.\Get-DeskSetup.ps1 -n m1    # -> m1.txt
```

> **Note:** If PowerShell blocks the script, run once:
> ```powershell
> Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
> ```

---

## Individual Scripts

| Script | Purpose |
|---|---|
| `Get-DisplaySettings.ps1` | Display info only |
| `Get-SoundSettings.ps1` | Default audio device only |

---

## Requirements

- Windows 10 / 11
- PowerShell 5.1 or later (pre-installed on Windows)
- No additional modules required
