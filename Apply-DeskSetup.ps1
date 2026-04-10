# Apply-DeskSetup.ps1
# Applies a saved desk profile by changing only:
# 1) Multi-display mode
# 2) Default audio output device
# It does NOT change resolution or refresh rate.
#
# Usage:
#   .\Apply-DeskSetup.ps1 -n m1
#   .\Apply-DeskSetup.ps1 -ProfilePath .\output\m1.json

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Alias("n")]
    [string] $Name,
    [string] $ProfilePath
)

# Resolve profile path: explicit path > name > latest json in output/
if (-not $ProfilePath) {
    $outputDir = Join-Path $PSScriptRoot "output"
    if ($Name) {
        $ProfilePath = Join-Path $outputDir "$Name.json"
    } else {
        $latest = Get-ChildItem -Path $outputDir -Filter "*.json" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($latest) {
            $ProfilePath = $latest.FullName
        }
    }
}

if (-not $ProfilePath -or -not (Test-Path $ProfilePath)) {
    throw "Profile JSON not found. Use -n <name> or -ProfilePath <path-to-json>."
}

$profile = Get-Content -Path $ProfilePath -Raw | ConvertFrom-Json

if (-not $profile.MultiDisplayMode) {
    throw "Profile missing MultiDisplayMode in $ProfilePath"
}
if (-not $profile.DefaultAudioOutput -or -not $profile.DefaultAudioOutput.Id) {
    throw "Profile missing DefaultAudioOutput.Id in $ProfilePath"
}

# Map the saved mode text to DisplaySwitch arguments.
$displaySwitchArg = switch -Regex ($profile.MultiDisplayMode) {
    "^Extended$" { "/extend"; break }
    "^Duplicate$" { "/clone"; break }
    "^Show Only 1" { "/internal"; break }
    "^Show Only External$" { "/external"; break }
    default { throw "Unsupported MultiDisplayMode '$($profile.MultiDisplayMode)' in profile." }
}

# Native COM wrapper to set default audio endpoint by device id.
if (-not ([System.Management.Automation.PSTypeName]'DeskAudioApply').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public enum ERole {
    eConsole = 0,
    eMultimedia = 1,
    eCommunications = 2
}

[ComImport, Guid("f8679f50-850a-41cf-9c72-430f290290c8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IPolicyConfig {
    int GetMixFormat(string pszDeviceName, IntPtr ppFormat);
    int GetDeviceFormat(string pszDeviceName, int bDefault, IntPtr ppFormat);
    int ResetDeviceFormat(string pszDeviceName);
    int SetDeviceFormat(string pszDeviceName, IntPtr pEndpointFormat, IntPtr MixFormat);
    int GetProcessingPeriod(string pszDeviceName, int bDefault, IntPtr pmftDefaultPeriod, IntPtr pmftMinimumPeriod);
    int SetProcessingPeriod(string pszDeviceName, IntPtr pmftPeriod);
    int GetShareMode(string pszDeviceName, IntPtr pMode);
    int SetShareMode(string pszDeviceName, IntPtr pMode);
    int GetPropertyValue(string pszDeviceName, IntPtr key, IntPtr pv);
    int SetPropertyValue(string pszDeviceName, IntPtr key, IntPtr pv);
    int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string wszDeviceId, ERole role);
    int SetEndpointVisibility(string pszDeviceName, int bVisible);
}

public static class DeskAudioApply {
    public static void SetDefaultById(string deviceId) {
        Type policyConfigType = Type.GetTypeFromCLSID(new Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9"));
        object policyConfig = Activator.CreateInstance(policyConfigType);
        IPolicyConfig pc = (IPolicyConfig)policyConfig;

        pc.SetDefaultEndpoint(deviceId, ERole.eConsole);
        pc.SetDefaultEndpoint(deviceId, ERole.eMultimedia);
        pc.SetDefaultEndpoint(deviceId, ERole.eCommunications);
    }
}
"@
}

if ($PSCmdlet.ShouldProcess("Display", "Set mode to $($profile.MultiDisplayMode)")) {
    Start-Process -FilePath "$env:WINDIR\System32\DisplaySwitch.exe" -ArgumentList $displaySwitchArg -Wait
}

if ($PSCmdlet.ShouldProcess("Audio", "Set default output to $($profile.DefaultAudioOutput.Name)")) {
    [DeskAudioApply]::SetDefaultById([string]$profile.DefaultAudioOutput.Id)
}

Write-Host "Applied profile: $ProfilePath" -ForegroundColor Green
Write-Host "Display mode: $($profile.MultiDisplayMode)" -ForegroundColor Green
Write-Host "Default audio: $($profile.DefaultAudioOutput.Name)" -ForegroundColor Green
