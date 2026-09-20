<#
    Setup-OBS.ps1  -  One-time configuration for the native-resolution game recorder.

    Creates an OBS profile "GameRec" and scene collection "GameRec", and enables
    the obs-websocket server (127.0.0.1:4455, no password) that GameRec.ps1 uses.

    It auto-detects your PRIMARY monitor's native resolution (the capture/base
    canvas) and, by default, ENCODES a downscaled 1080p copy at 60fps. Capturing
    native but encoding smaller is what keeps games smooth and keeps recordings
    playable - encoding full 4K at high quality saturates most GPU encoders and
    produces files too big to play back smoothly.

    Close OBS before running this (so it doesn't overwrite the files on exit).

    Examples:
        .\Setup-OBS.ps1                          # native capture -> 1080p60 NVENC
        .\Setup-OBS.ps1 -OutputHeight 1440       # encode 1440p instead
        .\Setup-OBS.ps1 -OutputHeight 0          # encode at full native resolution
        .\Setup-OBS.ps1 -Fps 30                  # 30fps
        .\Setup-OBS.ps1 -Quality high            # bigger files, higher quality
        .\Setup-OBS.ps1 -Encoder qsv             # Intel QuickSync instead of NVENC
        .\Setup-OBS.ps1 -Encoder x264            # software (any GPU)
#>
[CmdletBinding()]
param(
    # Capture (base canvas) resolution. Defaults to the primary monitor's native mode.
    [int]$Width,
    [int]$Height,
    # Encoded output height. 0 = encode at the full base resolution.
    [int]$OutputHeight = 1080,
    [int]$Fps = 60,
    [ValidateSet('nvenc', 'qsv', 'amd', 'x264')]
    [string]$Encoder = 'nvenc',
    # balanced = CQP 23 (small, smooth playback); high = CQP 16 (huge files).
    [ValidateSet('balanced', 'high')]
    [string]$Quality = 'balanced',
    [string]$RecordDir = "$env:USERPROFILE\Downloads\recordings",
    [int]$Port = 4455,
    # Keep OBS's live preview rendering (costs GPU even when not recording).
    [switch]$KeepPreview,
    # Overwrite an existing GameRec scene collection instead of leaving it alone.
    [switch]$ResetScenes
)
$ErrorActionPreference = 'Stop'

function Set-IniValues {
    <#
        Merges keys into an INI file, preserving every other line. OBS owns these
        files (they hold window geometry, dock layout, GUIDs); rewriting them
        wholesale throws that away and loses settings on the next OBS launch.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Data,
        # Only add keys that are missing; never change ones OBS already wrote.
        [switch]$OnlyIfMissing
    )
    $lines = New-Object System.Collections.ArrayList
    if (Test-Path -LiteralPath $Path) {
        foreach ($l in @(Get-Content -LiteralPath $Path)) { [void]$lines.Add($l) }
    }
    foreach ($section in $Data.Keys) {
        foreach ($key in $Data[$section].Keys) {
            $value = [string]$Data[$section][$key]

            $secIdx = -1
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i].Trim() -eq "[$section]") { $secIdx = $i; break }
            }
            if ($secIdx -lt 0) {
                if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -ne '') { [void]$lines.Add('') }
                [void]$lines.Add("[$section]")
                [void]$lines.Add("$key=$value")
                continue
            }

            $end = $lines.Count
            for ($i = $secIdx + 1; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match '^\s*\[.+\]\s*$') { $end = $i; break }
            }
            $found = $false
            for ($i = $secIdx + 1; $i -lt $end; $i++) {
                if ($lines[$i] -match ('^\s*' + [regex]::Escape($key) + '\s*=')) {
                    if (-not $OnlyIfMissing) { $lines[$i] = "$key=$value" }
                    $found = $true
                    break
                }
            }
            if (-not $found) {
                $insert = $end
                while ($insert -gt ($secIdx + 1) -and $lines[$insert - 1].Trim() -eq '') { $insert-- }
                $lines.Insert($insert, "$key=$value")
            }
        }
    }
    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

# OBS stores Windows paths with escaped backslashes in its INI files.
function ConvertTo-IniPath { param([string]$p) return $p.Replace('\', '\\') }

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

# Encoded resolution: downscale from the captured canvas unless told otherwise.
$OutCX = $Width
$OutCY = $Height
if ($OutputHeight -gt 0 -and $OutputHeight -lt $Height) {
    $OutCY = $OutputHeight
    $OutCX = [int][math]::Round($Width * ($OutputHeight / $Height))
    if ($OutCX % 2) { $OutCX++ }   # encoders require even dimensions
    if ($OutCY % 2) { $OutCY++ }
}
$downscaling = ($OutCX -ne $Width) -or ($OutCY -ne $Height)
# Bilinear is the cheapest downscale filter; bicubic only matters at 1:1.
$scaleType = if ($downscaling) { 'bilinear' } else { 'bicubic' }

# OBS Simple output: "HQ" means CQP 16, anything else means CQP 23.
# (Simple output builds the recording encoder with its own defaults for
# everything else - the per-encoder speed preset keys only affect streaming.)
$recQuality = if ($Quality -eq 'high') { 'HQ' } else { 'Small' }

$cfg     = Get-OBSConfigDir
$prof    = Join-Path $cfg 'basic\profiles\GameRec'
$scenes  = Join-Path $cfg 'basic\scenes'
$wsdir   = Join-Path $cfg 'plugin_config\obs-websocket'
New-Item -ItemType Directory -Force -Path $cfg, $prof, $scenes, $wsdir, $RecordDir | Out-Null

# OBS 30+ keeps per-user settings (tray, preview, active profile) in user.ini.
# Older builds keep them in global.ini. Write both so either version behaves.
$globalIni = Join-Path $cfg 'global.ini'
$userIni   = Join-Path $cfg 'user.ini'
$basicSel  = @{
    Profile = 'GameRec'; ProfileDir = 'GameRec'
    SceneCollection = 'GameRec'; SceneCollectionFile = 'GameRec'
}

Set-IniValues -Path $globalIni -Data @{ General = @{ FirstRun = 'true' } }
Set-IniValues -Path $globalIni -Data @{ Basic = $basicSel } -OnlyIfMissing

# Keeping the preview on makes OBS re-render the whole canvas continuously, which
# costs GPU time even while idle. Minimizing to the tray keeps it out of the way.
Set-IniValues -Path $userIni -Data @{
    General     = @{ FirstRun = 'true'; ConfirmOnExit = 'false' }
    BasicWindow = @{
        PreviewEnabled       = $(if ($KeepPreview) { 'true' } else { 'false' })
        SysTrayEnabled       = 'true'
        SysTrayWhenStarted   = 'true'
        SysTrayMinimizeToTray = 'true'
    }
}
Set-IniValues -Path $userIni -Data @{ Basic = $basicSel } -OnlyIfMissing

# --- profile basic.ini : resolution, fps, Simple output, chosen encoder, MP4 ---
$simpleOutput = [ordered]@{
    FilePath   = (ConvertTo-IniPath $RecordDir)
    RecFormat2 = 'mp4'
    RecQuality = $recQuality
    RecEncoder = $Encoder
    VBitrate   = 2500
    ABitrate   = 160
    RecTracks  = 1
    UseAdvanced = 'false'
}

Set-IniValues -Path (Join-Path $prof 'basic.ini') -Data @{
    General = @{ Name = 'GameRec' }
    Video   = [ordered]@{
        BaseCX = $Width; BaseCY = $Height
        OutputCX = $OutCX; OutputCY = $OutCY
        FPSType = 0; FPSCommon = $Fps; FPSInt = $Fps; FPSNum = $Fps; FPSDen = 1
        ScaleType = $scaleType
        ColorFormat = 'NV12'; ColorSpace = '709'; ColorRange = 'Partial'
    }
    Output       = @{ Mode = 'Simple'; FilenameFormatting = '%CCYY-%MM-%DD %hh-%mm-%ss' }
    SimpleOutput = $simpleOutput
    Audio        = @{ SampleRate = 48000; ChannelSetup = 'Stereo' }
}

# --- scene collection : one scene "Game" (sources are added by GameRec.ps1) ---
$sceneFile = Join-Path $scenes 'GameRec.json'
if ($ResetScenes -or -not (Test-Path $sceneFile)) {
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
"@ | Set-Content -Path $sceneFile -Encoding UTF8
}

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
Write-Host ("  Capture    : {0}x{1} @ {2}fps" -f $Width, $Height, $Fps)
if ($downscaling) {
    Write-Host ("  Encoded as : {0}x{1}  (use -OutputHeight 0 to encode at full size)" -f $OutCX, $OutCY)
} else {
    Write-Host ("  Encoded as : {0}x{1}  (full size - heavy on the GPU and on playback)" -f $OutCX, $OutCY) -ForegroundColor Yellow
}
Write-Host ("  Encoder    : {0} (quality {1})" -f $Encoder, $recQuality)
Write-Host ("  Preview    : {0}" -f $(if ($KeepPreview) { 'on' } else { 'off (saves GPU while idle)' }))
Write-Host ("  Output     : {0}" -f $RecordDir)
Write-Host ("  WebSocket  : 127.0.0.1:{0} (no password)" -f $Port)
Write-Host ("  Config dir : {0}" -f $cfg)
Write-Host ""
Write-Host "Now use launcher\Start-Recording.cmd (or: .\GameRec.ps1 start)." -ForegroundColor Cyan
