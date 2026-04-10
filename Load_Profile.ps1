# Load_Profile.ps1
# Applies the saved display and audio settings for the given profile number.
# Usage: .\Load_Profile.ps1 -n 1

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ $_ -ge 1 })]
    [int] $n,
    [string] $ProfilesDir = (Join-Path $PSScriptRoot "SetDesk Profiles"),
    [string] $Prefix = "profile_",
    [switch] $WhatIfApply
)

$libScript   = Join-Path $PSScriptRoot "lib\Apply-DeskSetup.ps1"

& $libScript -ProfilePath (Join-Path $ProfilesDir "$Prefix$n.json") -WhatIf:$WhatIfApply
