# Get-DisplaySettings.ps1
# Purpose: save a human-readable display report to a text file.
#
# Usage:
#   .\Get-DisplaySettings.ps1          -> saves as display-settings_<timestamp>.txt
#   .\Get-DisplaySettings.ps1 -n m1    -> saves as m1.txt
#
# Why this script uses C#:
param(
    [Alias("n")]
    [string] $Name,      # Optional custom filename (without .txt)
    [string] $OutputDir  # Optional output folder; defaults to project output/
)
#
# - Windows stores display topology (Extended / Duplicate / Show only X) in low-level APIs.
# - PowerShell has no simple built-in cmdlet for that, so we call user32.dll through Add-Type.

# Load helper type only once per PowerShell session.
# This avoids "type already exists" errors when running the script repeatedly.
if (-not ([System.Management.Automation.PSTypeName]'DisplayHelper').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public static class DisplayHelper {
    const uint QDC_ONLY_ACTIVE_PATHS = 0x00000002;
    const uint QDC_DATABASE_CURRENT  = 0x00000004;
    const int GET_TARGET_NAME        = 2;
    const int MODE_TYPE_SOURCE       = 1;

    [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out uint pathCount, out uint modeCount);
    [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint pathCount, [Out] PATH_INFO[] paths, ref uint modeCount, [Out] MODE_INFO[] modes, out TOPOLOGY_ID topologyId);
    [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint pathCount, [Out] PATH_INFO[] paths, ref uint modeCount, [Out] MODE_INFO[] modes, IntPtr topologyId);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref TARGET_NAME request);

    public enum TOPOLOGY_ID { Internal = 1, Clone = 2, Extend = 4, External = 8 }

    [StructLayout(LayoutKind.Sequential)] public struct LUID { public uint Low; public int High; }
    [StructLayout(LayoutKind.Sequential)] public struct RATIONAL { public uint N; public uint D; }
    [StructLayout(LayoutKind.Sequential)] public struct POINTL { public int x; public int y; }

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
    public struct MODE_UNION {
        [FieldOffset(0)] public SOURCE_MODE sourceMode;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MODE_INFO { public int infoType; public uint id; public LUID adapterId; public MODE_UNION modeInfo; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct TARGET_NAME {
        public int headerType; public uint headerSize; public LUID headerAdapterId; public uint headerId;
        public uint flags; public int outputTechnology;
        public ushort edidManufactureId; public ushort edidProductCodeId; public uint connectorInstance;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string monitorFriendlyDeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string monitorDevicePath;
    }

    public class MonitorInfo {
        public string Name;
        public uint Width;
        public uint Height;
        public double RefreshHz;
        public int Index;
    }

    // Returns current Windows multi-display mode: Extend, Duplicate, etc.
    public static string GetTopology() {
        uint pathCount, modeCount;
        GetDisplayConfigBufferSizes(QDC_DATABASE_CURRENT, out pathCount, out modeCount);

        var paths = new PATH_INFO[pathCount];
        var modes = new MODE_INFO[modeCount];
        TOPOLOGY_ID topologyId;

        int ret = QueryDisplayConfig(QDC_DATABASE_CURRENT, ref pathCount, paths, ref modeCount, modes, out topologyId);
        if (ret != 0) return "Unknown (error " + ret + ")";

        switch (topologyId) {
            case TOPOLOGY_ID.Internal: return "Show Only 1 (Internal / Laptop screen)";
            case TOPOLOGY_ID.Clone:    return "Duplicate";
            case TOPOLOGY_ID.Extend:   return "Extended";
            case TOPOLOGY_ID.External: return "Show Only External";
            default:                   return topologyId.ToString();
        }
    }

    // Returns active monitor list with name + refresh + (best-effort) resolution.
    public static List<MonitorInfo> GetMonitors() {
        uint pathCount, modeCount;
        GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out pathCount, out modeCount);

        var paths = new PATH_INFO[pathCount];
        var modes = new MODE_INFO[modeCount];
        QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref pathCount, paths, ref modeCount, modes, IntPtr.Zero);

        var result = new List<MonitorInfo>();
        var seenPaths = new HashSet<string>();

        for (int i = 0; i < (int)pathCount; i++) {
            var path = paths[i];

            // Ask Windows for the friendly monitor name.
            var request = new TARGET_NAME();
            request.headerType = GET_TARGET_NAME;
            request.headerSize = (uint)Marshal.SizeOf(request);
            request.headerAdapterId = path.targetInfo.adapterId;
            request.headerId = path.targetInfo.id;
            DisplayConfigGetDeviceInfo(ref request);

            string name = string.IsNullOrWhiteSpace(request.monitorFriendlyDeviceName)
                ? "Unknown Monitor"
                : request.monitorFriendlyDeviceName;

            // Best-effort resolution lookup. Some systems return 0x0 for certain paths.
            uint width = 0;
            uint height = 0;
            uint sourceIndex = path.sourceInfo.modeInfoIdx;
            if (sourceIndex != 0xFFFFFFFF && sourceIndex < modeCount && modes[sourceIndex].infoType == MODE_TYPE_SOURCE) {
                width = modes[sourceIndex].modeInfo.sourceMode.width;
                height = modes[sourceIndex].modeInfo.sourceMode.height;
            }

            // Convert rational refresh rate to a decimal Hz value.
            double refreshHz = 0;
            if (path.targetInfo.refreshRate.D != 0) {
                refreshHz = Math.Round((double)path.targetInfo.refreshRate.N / path.targetInfo.refreshRate.D, 3);
            }

            // De-duplicate mirrored/duplicate paths by device path.
            string uniqueKey = request.monitorDevicePath;
            if (!seenPaths.Contains(uniqueKey)) {
                seenPaths.Add(uniqueKey);
                result.Add(new MonitorInfo {
                    Name = name,
                    Width = width,
                    Height = height,
                    RefreshHz = refreshHz,
                    Index = result.Count + 1
                });
            }
        }

        return result;
    }
}
"@
}

# We build the report as plain text lines, then save once at the end.
$lines = [System.Collections.Generic.List[string]]::new()

# Report header.
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$lines.Add("Display Settings Report")
$lines.Add("Generated: $timestamp")
$lines.Add("=" * 40)

# Section 1: overall Windows display mode.
$lines.Add("")
$lines.Add("===== Multi-Display Mode =====")
$lines.Add("  Mode: $([DisplayHelper]::GetTopology())")

# Section 2: active monitor details.
$lines.Add("")
$lines.Add("===== Active Monitors =====")
$monitors = [DisplayHelper]::GetMonitors()

if ($monitors.Count -eq 0) {
    $lines.Add("  No active monitors detected.")
} else {
    foreach ($monitor in $monitors) {
        $lines.Add("")
        $lines.Add("  Monitor $($monitor.Index): $($monitor.Name)")
        $lines.Add("    Resolution   : $($monitor.Width) x $($monitor.Height)")
        $lines.Add("    Refresh Rate : $($monitor.RefreshHz) Hz")
    }
}

$lines.Add("")
$lines.Add("Done.")

# Save report — use custom name if -n was given, otherwise use a timestamp.
if (-not $OutputDir) {
    $OutputDir = Join-Path (Split-Path $PSScriptRoot -Parent) "output"
}
if (-not (Test-Path $OutputDir)) {
    New-Item -Path $OutputDir -ItemType Directory | Out-Null
}

if ($Name) {
    $outputFile = Join-Path $OutputDir "$Name.txt"
} else {
    $outputFile = Join-Path $OutputDir "display-settings_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').txt"
}
$lines | Set-Content -Path $outputFile -Encoding UTF8

Write-Host "Saved to: $outputFile" -ForegroundColor Green
