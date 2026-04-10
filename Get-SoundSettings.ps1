# Get-SoundSettings.ps1
# Shows only the default audio output device — the one Windows is currently playing sound through.
#
# Usage:
#   .\Get-SoundSettings.ps1         -> saves as sound-settings_<timestamp>.txt
#   .\Get-SoundSettings.ps1 -n m1   -> saves as m1.txt

param(
    [Alias("n")]
    [string] $Name   # Optional custom filename (without .txt)
)

# ---- Step 1: Load a small C# helper (only once per PowerShell session) ----
# PowerShell has no built-in way to ask "what is the default audio device?".
# We use a C# COM wrapper around the Windows IMMDeviceEnumerator API to get it.
if (-not ([System.Management.Automation.PSTypeName]'AudioHelper').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

// COM interface: the Windows audio device manager.
[ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceEnumerator {
    int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr ppDevices);
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppEndpoint);
    int GetDevice(string pwstrId, out IMMDevice ppDevice);
    int RegisterEndpointNotificationCallback(IntPtr p);
    int UnregisterEndpointNotificationCallback(IntPtr p);
}

// COM interface: represents a single audio device.
[ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDevice {
    int Activate(ref Guid iid, int ctx, IntPtr p, out IntPtr pp);
    int OpenPropertyStore(int access, out IntPtr ppStore);
    int GetId([MarshalAs(UnmanagedType.LPWStr)] out string ppstrId);
    int GetState(out int pdwState);
}

// COM class: the concrete enumerator object we create.
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"), ClassInterface(ClassInterfaceType.None)]
public class MMDeviceEnumeratorClass { }

public static class AudioHelper {
    public static string GetDefaultDeviceId() {
        // Create the enumerator, then ask for the default render (output) device.
        // 0, 0 = eRender (speakers/headphones), eConsole (standard playback role)
        var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorClass();
        IMMDevice device;
        enumerator.GetDefaultAudioEndpoint(0, 0, out device);
        string id;
        device.GetId(out id);
        return id;   // e.g. "{0.0.0.00000000}.{GUID}"
    }
}
"@
}

# ---- Step 2: Get the device ID and match it to a friendly name in the registry ----
# The device ID contains the device GUID. Windows stores friendly names in the registry
# under HKLM:\...\MMDevices\Audio\Render, one subfolder per audio device.
$deviceId = [AudioHelper]::GetDefaultDeviceId()

$friendlyName = "Unknown"
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render"
foreach ($dev in Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue) {
    # Check if the registry folder GUID appears inside the device ID string.
    if ($deviceId -like "*$($dev.PSChildName)*") {
        $props = Get-ItemProperty -Path "$($dev.PSPath)\Properties" -ErrorAction SilentlyContinue
        # {a45c254e...},2 is the Windows standard property for "device friendly name".
        $friendlyName = $props."{a45c254e-df1c-4efd-8020-67d146a850e0},2"
        break
    }
}

# ---- Step 3: Build the report ----
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("Sound Settings Report")
$lines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$lines.Add("=" * 40)
$lines.Add("")
$lines.Add("===== Default Audio Output Device =====")
$lines.Add("  Name: $friendlyName")
$lines.Add("")
$lines.Add("Done.")

# ---- Step 4: Save to file ----
# Use custom name if -n was given, otherwise fall back to a timestamp.
if ($Name) {
    $outputFile = Join-Path $PSScriptRoot "$Name.txt"
} else {
    $outputFile = Join-Path $PSScriptRoot "sound-settings_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').txt"
}
$lines | Set-Content -Path $outputFile -Encoding UTF8

Write-Host "Saved to: $outputFile" -ForegroundColor Green


Write-Host "Saved to: $outputFile" -ForegroundColor Green
