# Save_Profile.ps1
# Saves the current display and audio settings as the given profile number.
# Usage: .\Save_Profile.ps1 -n 1

param(
    [Parameter(Mandatory)]
    [ValidateScript({ $_ -ge 1 })]
    [int] $n,
    [string] $ProfilesDir = (Join-Path $PSScriptRoot "SetDesk Profiles"),
    [string] $Prefix = "profile_"
)

$libScript   = Join-Path $PSScriptRoot "lib\Get-DeskSetup.ps1"

& $libScript -n "$Prefix$n" -OutputDir $ProfilesDir
