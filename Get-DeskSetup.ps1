# Get-SystemSettings.ps1
# Saves a combined display + audio report to a single text file.
#
# Usage:
#   .\Get-SystemSettings.ps1          -> saves as system-settings_<timestamp>.txt
#   .\Get-SystemSettings.ps1 -n m1    -> saves as m1.txt

param(
    [Alias("n")]
    [string] $Name   # Optional custom filename (without .txt)
)

# ===========================================================================
# DISPLAY HELPER  (calls user32.dll to read topology and monitor info)
# ===========================================================================
if (-not ([System.Management.Automation.PSTypeName]'DisplayHelper').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public static class DisplayHelper {
    const uint QDC_ONLY_ACTIVE_PATHS = 0x00000002;
    const uint QDC_DATABASE_CURRENT  = 0x00000004;
    const int  GET_SOURCE_NAME       = 1;  // get the GDI device name e.g. \\.\DISPLAY1
    const int  GET_TARGET_NAME       = 2;  // get the friendly monitor name
    const int  MODE_TYPE_SOURCE      = 1;

    [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out uint pathCount, out uint modeCount);
    [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint pathCount, [Out] PATH_INFO[] paths, ref uint modeCount, [Out] MODE_INFO[] modes, out TOPOLOGY_ID topologyId);
    [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint pathCount, [Out] PATH_INFO[] paths, ref uint modeCount, [Out] MODE_INFO[] modes, IntPtr topologyId);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref TARGET_NAME request);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref SOURCE_NAME request);

    public enum TOPOLOGY_ID { Internal = 1, Clone = 2, Extend = 4, External = 8 }

    [StructLayout(LayoutKind.Sequential)] public struct LUID     { public uint Low; public int High; }
    [StructLayout(LayoutKind.Sequential)] public struct RATIONAL { public uint N;   public uint D;  }
    [StructLayout(LayoutKind.Sequential)] public struct POINTL   { public int  x;   public int  y;  }

    [StructLayout(LayoutKind.Sequential)]
    public struct PATH_SOURCE { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint statusFlags; }

    [StructLayout(LayoutKind.Sequential)]
    public struct PATH_TARGET {
        public LUID adapterId; public uint id; public uint modeInfoIdx;
        public int outputTechnology; public int rotation; public int scaling;
        public RATIONAL refreshRate; public int scanLineOrdering;
        [MarshalAs(UnmanagedType.Bool)] public bool targetAvailable;
        public uint statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PATH_INFO { public PATH_SOURCE sourceInfo; public PATH_TARGET targetInfo; public uint flags; }

    [StructLayout(LayoutKind.Sequential)]
    public struct SOURCE_MODE { public uint width; public uint height; public int pixelFormat; public POINTL position; }

    [StructLayout(LayoutKind.Explicit, Size = 64)]
    public struct MODE_UNION { [FieldOffset(0)] public SOURCE_MODE sourceMode; }

    [StructLayout(LayoutKind.Sequential)]
    public struct MODE_INFO { public int infoType; public uint id; public LUID adapterId; public MODE_UNION modeInfo; }

    // Holds the GDI device name (e.g. "\\.\DISPLAY1") for a given display source.
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct SOURCE_NAME {
        public int headerType; public uint headerSize; public LUID headerAdapterId; public uint headerId;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string viewGdiDeviceName;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct TARGET_NAME {
        public int headerType; public uint headerSize; public LUID headerAdapterId; public uint headerId;
        public uint flags; public int outputTechnology;
        public ushort edidManufactureId; public ushort edidProductCodeId; public uint connectorInstance;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst =  64)] public string monitorFriendlyDeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string monitorDevicePath;
    }

    public class MonitorInfo { public string Name; public uint Width; public uint Height; public double RefreshHz; public int Index; public bool IsPrimary; public string SourceDeviceName; }

    // Returns current Windows multi-display mode (Extended / Duplicate / etc.)
    public static string GetTopology() {
        uint pathCount, modeCount;
        GetDisplayConfigBufferSizes(QDC_DATABASE_CURRENT, out pathCount, out modeCount);
        var paths = new PATH_INFO[pathCount];
        var modes = new MODE_INFO[modeCount];
        TOPOLOGY_ID topologyId;
        int ret = QueryDisplayConfig(QDC_DATABASE_CURRENT, ref pathCount, paths, ref modeCount, modes, out topologyId);
        if (ret != 0) return "Unknown (error " + ret + ")";
        switch (topologyId) {
            case TOPOLOGY_ID.Internal: return "Show Only 1 (Internal)";
            case TOPOLOGY_ID.Clone:    return "Duplicate";
            case TOPOLOGY_ID.Extend:   return "Extended";
            case TOPOLOGY_ID.External: return "Show Only External";
            default:                   return topologyId.ToString();
        }
    }

    // Returns active monitor list with name, refresh rate, and best-effort resolution.
    public static List<MonitorInfo> GetMonitors() {
        uint pathCount, modeCount;
        GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out pathCount, out modeCount);
        var paths = new PATH_INFO[pathCount];
        var modes = new MODE_INFO[modeCount];
        QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref pathCount, paths, ref modeCount, modes, IntPtr.Zero);

        var result    = new List<MonitorInfo>();
        var seenPaths = new HashSet<string>();

        for (int i = 0; i < (int)pathCount; i++) {
            var path = paths[i];

            var request = new TARGET_NAME();
            request.headerType      = GET_TARGET_NAME;
            request.headerSize      = (uint)Marshal.SizeOf(request);
            request.headerAdapterId = path.targetInfo.adapterId;
            request.headerId        = path.targetInfo.id;
            DisplayConfigGetDeviceInfo(ref request);

            string name = string.IsNullOrWhiteSpace(request.monitorFriendlyDeviceName)
                ? "Unknown Monitor" : request.monitorFriendlyDeviceName;

            // Get the GDI source device name (e.g. "\\.\DISPLAY1") so we can
            // match against Screen.PrimaryScreen.DeviceName in PowerShell.
            var srcReq = new SOURCE_NAME();
            srcReq.headerType      = GET_SOURCE_NAME;
            srcReq.headerSize      = (uint)Marshal.SizeOf(srcReq);
            srcReq.headerAdapterId = path.sourceInfo.adapterId;
            srcReq.headerId        = path.sourceInfo.id;
            DisplayConfigGetDeviceInfo(ref srcReq);
            string sourceDeviceName = srcReq.viewGdiDeviceName ?? "";

            uint width = 0, height = 0;
            bool isPrimary = false;
            uint sourceIndex = path.sourceInfo.modeInfoIdx;
            if (sourceIndex != 0xFFFFFFFF && sourceIndex < modeCount && modes[sourceIndex].infoType == MODE_TYPE_SOURCE) {
                width     = modes[sourceIndex].modeInfo.sourceMode.width;
                height    = modes[sourceIndex].modeInfo.sourceMode.height;
                // Primary display is always positioned at (0, 0) in Windows.
                isPrimary = modes[sourceIndex].modeInfo.sourceMode.position.x == 0
                         && modes[sourceIndex].modeInfo.sourceMode.position.y == 0;
            }

            double refreshHz = 0;
            if (path.targetInfo.refreshRate.D != 0)
                refreshHz = Math.Round((double)path.targetInfo.refreshRate.N / path.targetInfo.refreshRate.D, 3);

            string uniqueKey = request.monitorDevicePath;
            if (!seenPaths.Contains(uniqueKey)) {
                seenPaths.Add(uniqueKey);
                result.Add(new MonitorInfo { Name = name, Width = width, Height = height, RefreshHz = refreshHz, Index = result.Count + 1, IsPrimary = isPrimary, SourceDeviceName = sourceDeviceName });
            }
        }
        return result;
    }
}
"@
}

# ===========================================================================
# AUDIO HELPER  (calls IMMDeviceEnumerator COM API to get default device)
# ===========================================================================
if (-not ([System.Management.Automation.PSTypeName]'AudioHelper').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

[ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceEnumerator {
    int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr ppDevices);
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppEndpoint);
    int GetDevice(string pwstrId, out IMMDevice ppDevice);
    int RegisterEndpointNotificationCallback(IntPtr p);
    int UnregisterEndpointNotificationCallback(IntPtr p);
}

[ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDevice {
    int Activate(ref Guid iid, int ctx, IntPtr p, out IntPtr pp);
    int OpenPropertyStore(int access, out IntPtr ppStore);
    int GetId([MarshalAs(UnmanagedType.LPWStr)] out string ppstrId);
    int GetState(out int pdwState);
}

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"), ClassInterface(ClassInterfaceType.None)]
public class MMDeviceEnumeratorClass { }

public static class AudioHelper {
    public static string GetDefaultDeviceId() {
        // 0, 0 = eRender (output), eConsole (standard playback role)
        var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorClass();
        IMMDevice device;
        enumerator.GetDefaultAudioEndpoint(0, 0, out device);
        string id;
        device.GetId(out id);
        return id;
    }
}
"@
}

# ===========================================================================
# BUILD THE REPORT
# ===========================================================================
$lines = [System.Collections.Generic.List[string]]::new()

# Header
$lines.Add("System Settings Report")
$lines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$lines.Add("=" * 40)

# --- Section 1: Display mode ---
$lines.Add("")
$lines.Add("===== Multi-Display Mode =====")
$lines.Add("  Mode: $([DisplayHelper]::GetTopology())")

# --- Section 2: Monitors ---
# Use Screen.PrimaryScreen to reliably identify the main display by its GDI device name.
Add-Type -AssemblyName System.Windows.Forms
$primaryDeviceName = [System.Windows.Forms.Screen]::PrimaryScreen.DeviceName  # e.g. "\\.\DISPLAY1"

$lines.Add("")
$lines.Add("===== Active Monitors =====")
$monitors = [DisplayHelper]::GetMonitors()
if ($monitors.Count -eq 0) {
    $lines.Add("  No active monitors detected.")
} else {
    foreach ($monitor in $monitors) {
        $lines.Add("")
        $isMain = $monitor.SourceDeviceName -eq $primaryDeviceName
        $lines.Add("  Monitor $($monitor.Index): $($monitor.Name)")
        $lines.Add("    Main         : $(if ($isMain) { 'Yes' } else { 'No' })")
        $lines.Add("    Resolution   : $($monitor.Width) x $($monitor.Height)")
        $lines.Add("    Refresh Rate : $($monitor.RefreshHz) Hz")
    }
}

# --- Section 3: Default audio output ---
$lines.Add("")
$lines.Add("===== Default Audio Output Device =====")
$deviceId    = [AudioHelper]::GetDefaultDeviceId()
$friendlyName = "Unknown"
$regPath      = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render"
foreach ($dev in Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue) {
    if ($deviceId -like "*$($dev.PSChildName)*") {
        $props = Get-ItemProperty -Path "$($dev.PSPath)\Properties" -ErrorAction SilentlyContinue
        $friendlyName = $props."{a45c254e-df1c-4efd-8020-67d146a850e0},2"
        break
    }
}
$lines.Add("  Name: $friendlyName")

$lines.Add("")
$lines.Add("Done.")

# ===========================================================================
# SAVE TO FILE
# ===========================================================================
# Always save into the output/ subfolder next to this script.
$outputDir = Join-Path $PSScriptRoot "output"
if ($Name) {
    $outputFile = Join-Path $outputDir "$Name.txt"
} else {
    $outputFile = Join-Path $outputDir "desk-setup_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').txt"
}
$lines | Set-Content -Path $outputFile -Encoding UTF8

Write-Host "Saved to: $outputFile" -ForegroundColor Green
