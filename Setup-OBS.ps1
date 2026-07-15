<#
    Setup-OBS.ps1  -  One-time configuration for the 4K/60 game recorder.

    Creates an OBS profile "GameRec" and scene collection "GameRec", and enables
    the obs-websocket server (127.0.0.1:4455, no password) that GameRec.ps1 uses.

    By default it auto-detects your PRIMARY monitor's native resolution and sets
    60fps + NVIDIA NVENC. Override any of these with parameters.

    Close OBS before running this (so it doesn't overwrite the files on exit).

    Examples:
        .\Setup-OBS.ps1                        # auto-detect res, 60fps, NVENC
        .\Setup-OBS.ps1 -Fps 30                 # 30fps
        .\Setup-OBS.ps1 -Width 1920 -Height 1080
        .\Setup-OBS.ps1 -Encoder qsv            # Intel QuickSync instead of NVENC
        .\Setup-OBS.ps1 -Encoder x264           # software (any GPU)
#>
[CmdletBinding()]
param(
    [int]$Width,
    [int]$Height,
    [int]$Fps = 60,
    [ValidateSet('nvenc', 'qsv', 'amd', 'x264')]
    [string]$Encoder = 'nvenc',
    [string]$RecordDir = "$env:USERPROFILE\Downloads\recordings",
    [int]$Port = 4455
)
$ErrorActionPreference = 'Stop'

function Get-PrimaryResolution {
    # Returns physical pixels of the primary monitor (ignores Windows DPI scaling).
    Add-Type -AssemblyName System.Windows.Forms
    if (-not ('NativeDisp' -as [type])) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public class NativeDisp {
    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    private static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    private struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
    }
    // Returns { width, height, refreshHz } in physical pixels, or {0,0,0} on failure.
    public static int[] PrimaryMode(string dev) {
        DEVMODE dm = new DEVMODE();
        dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        if (EnumDisplaySettings(dev, -1, ref dm) && dm.dmPelsWidth > 0)
            return new int[] { dm.dmPelsWidth, dm.dmPelsHeight, dm.dmDisplayFrequency };
        return new int[] { 0, 0, 0 };
    }
}
"@
    }
    $primary = [System.Windows.Forms.Screen]::AllScreens | Where-Object { $_.Primary } | Select-Object -First 1
    if (-not $primary) { $primary = [System.Windows.Forms.Screen]::AllScreens | Select-Object -First 1 }
    $m = [NativeDisp]::PrimaryMode($primary.DeviceName)
    if ($m[0] -gt 0) { return @{ W = $m[0]; H = $m[1]; Hz = $m[2] } }
    # Fallback to (possibly DPI-scaled) bounds
    return @{ W = $primary.Bounds.Width; H = $primary.Bounds.Height; Hz = 60 }
}

function Get-OBSConfigDir {
    # scoop portable install keeps config next to the app; installer uses %APPDATA%.
    $scoop = "$env:USERPROFILE\scoop\apps\obs-studio\current"
    if ((Test-Path (Join-Path $scoop 'obs64.exe') -ErrorAction SilentlyContinue) -or (Test-Path (Join-Path $scoop 'portable_mode.txt'))) {
        return (Join-Path $scoop 'config\obs-studio')
    }
    $scoopBin = "$env:USERPROFILE\scoop\apps\obs-studio\current\bin\64bit\obs64.exe"
    if (Test-Path $scoopBin) { return (Join-Path $scoop 'config\obs-studio') }
    return "$env:APPDATA\obs-studio"
}

if (Get-Process obs64 -ErrorAction SilentlyContinue) {
    Write-Host "OBS is running. Close it first, then re-run this script." -ForegroundColor Yellow
    exit 1
}

if (-not $Width -or -not $Height) {
    $res = Get-PrimaryResolution
    if (-not $Width)  { $Width  = $res.W }
    if (-not $Height) { $Height = $res.H }
    Write-Host ("Detected primary monitor: {0}x{1} @ {2}Hz" -f $res.W, $res.H, $res.Hz) -ForegroundColor Cyan
}

$cfg     = Get-OBSConfigDir
$prof    = Join-Path $cfg 'basic\profiles\GameRec'
$scenes  = Join-Path $cfg 'basic\scenes'
$wsdir   = Join-Path $cfg 'plugin_config\obs-websocket'
New-Item -ItemType Directory -Force -Path $cfg, $prof, $scenes, $wsdir, $RecordDir | Out-Null

# --- global.ini : select our profile + scene collection, skip first-run wizard ---
@"
[General]
FirstRun=true
LastVersion=536936960

[Basic]
Profile=GameRec
ProfileDir=GameRec
SceneCollection=GameRec
SceneCollectionFile=GameRec
"@ | Set-Content -Path (Join-Path $cfg 'global.ini') -Encoding UTF8

# --- profile basic.ini : resolution, fps, Simple output, chosen encoder, MP4 ---
@"
[General]
Name=GameRec

[Video]
BaseCX=$Width
BaseCY=$Height
OutputCX=$Width
OutputCY=$Height
FPSType=0
FPSCommon=$Fps
ScaleType=bicubic
ColorFormat=NV12
ColorSpace=709
ColorRange=Partial

[Output]
Mode=Simple
FilenameFormatting=%CCYY-%MM-%DD %hh-%mm-%ss

[SimpleOutput]
FilePath=$RecordDir
RecFormat2=mp4
RecQuality=HQ
RecEncoder=$Encoder
VBitrate=2500
ABitrate=160
RecTracks=1

[Audio]
SampleRate=48000
ChannelSetup=Stereo
"@ | Set-Content -Path (Join-Path $prof 'basic.ini') -Encoding UTF8

# --- scene collection : one scene "Game" (sources are added by GameRec.ps1) ---
@"
{
  "current_scene": "Game",
  "current_program_scene": "Game",
  "scene_order": [ { "name": "Game" } ],
  "name": "GameRec",
  "sources": [
    {
      "balance": 0.5, "deinterlace_field_order": 0, "deinterlace_mode": 0,
      "enabled": true, "flags": 0, "hotkeys": {}, "id": "scene",
      "versioned_id": "scene", "mixers": 0, "monitoring_type": 0, "muted": false,
      "name": "Game", "prev_ver": 536936960, "private_settings": {},
      "push-to-mute": false, "push-to-mute-delay": 0, "push-to-talk": false,
      "push-to-talk-delay": 0,
      "settings": { "custom_size": false, "id_counter": 0, "items": [] },
      "sync": 0, "volume": 1.0
    }
  ]
}
"@ | Set-Content -Path (Join-Path $scenes 'GameRec.json') -Encoding UTF8

# --- obs-websocket : enabled, no auth, localhost:$Port ---
@"
{
  "alerts_enabled": false,
  "auth_required": false,
  "first_load": false,
  "server_enabled": true,
  "server_password": "",
  "server_port": $Port
}
"@ | Set-Content -Path (Join-Path $wsdir 'config.json') -Encoding UTF8

Write-Host ""
Write-Host "OBS configured for game recording:" -ForegroundColor Green
Write-Host ("  Resolution : {0}x{1} @ {2}fps" -f $Width, $Height, $Fps)
Write-Host ("  Encoder    : {0}" -f $Encoder)
Write-Host ("  Output     : {0}" -f $RecordDir)
Write-Host ("  WebSocket  : 127.0.0.1:{0} (no password)" -f $Port)
Write-Host ("  Config dir : {0}" -f $cfg)
Write-Host ""
Write-Host "Now use launcher\Start-Recording.cmd (or: .\GameRec.ps1 start)." -ForegroundColor Cyan
