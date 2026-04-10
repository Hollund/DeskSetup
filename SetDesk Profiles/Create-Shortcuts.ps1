# Create-Shortcuts.ps1
# Recreates all Save/Load shortcuts in this folder pointing to the root scripts.

param(
    [int[]] $ProfileNumbers = @(1, 2, 3, 4),
    [string] $RootPath = (Split-Path $PSScriptRoot -Parent),
    [string] $ShortcutDir = $PSScriptRoot,
    [ValidateSet("Hidden", "Normal", "Minimized", "Maximized")]
    [string] $WindowStyle = "Hidden",
    [string] $PowerShellExe
)

if (-not $PowerShellExe) {
    $PowerShellExe = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
    if (-not $PowerShellExe) { $PowerShellExe = Join-Path $PSHOME "powershell.exe" }
}

$wsh = New-Object -ComObject WScript.Shell

foreach ($n in $ProfileNumbers) {
    $saveLnk = Join-Path $ShortcutDir "Save Profile $n.lnk"
    $sc = $wsh.CreateShortcut($saveLnk)
    $sc.TargetPath       = $PowerShellExe
    $sc.Arguments        = "-NoProfile -ExecutionPolicy Bypass -WindowStyle $WindowStyle -File `"$RootPath\Save_Profile.ps1`" -n $n"
    $sc.WorkingDirectory = $RootPath
    $sc.IconLocation     = "shell32.dll,259"
    $sc.Save()

    $loadLnk = Join-Path $ShortcutDir "Load Profile $n.lnk"
    $sc2 = $wsh.CreateShortcut($loadLnk)
    $sc2.TargetPath       = $PowerShellExe
    $sc2.Arguments        = "-NoProfile -ExecutionPolicy Bypass -WindowStyle $WindowStyle -File `"$RootPath\Load_Profile.ps1`" -n $n"
    $sc2.WorkingDirectory = $RootPath
    $sc2.IconLocation     = "shell32.dll,137"
    $sc2.Save()

    Write-Host "Created: Save Profile $n  +  Load Profile $n"
}

Write-Host "`nDone. Shortcuts recreated in: $ShortcutDir" -ForegroundColor Green
