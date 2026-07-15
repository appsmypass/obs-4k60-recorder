<#
    GameRec.ps1  -  Manual 4K/60 game recorder (drives genuine OBS via websocket)

    USAGE:
        GameRec.ps1 start     # ensure OBS is running, then START recording
        GameRec.ps1 stop      # STOP recording and save the MP4
        GameRec.ps1 toggle    # start if stopped, stop if recording
        GameRec.ps1 status    # show whether OBS is recording + record folder

    Records your primary display at its native resolution and 60fps using your
    GPU hardware encoder (NVIDIA NVENC by default), with game sound + mic, to:
        %USERPROFILE%\Downloads\recordings\<date time>.mp4

    You start/stop it yourself (e.g. before/after a game). No auto game-detection.

    First-time setup: run Setup-OBS.ps1 once (configures the OBS profile + enables
    the websocket server this script talks to).
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('start', 'stop', 'toggle', 'status')]
    [string]$Action = 'toggle',
    [int]$Port = 4455
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'OBS-Control.ps1')

$RecDir = "$env:USERPROFILE\Downloads\recordings"

function Write-Info($m) { Write-Host $m -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host $m -ForegroundColor Green }
function Write-Warn($m) { Write-Host $m -ForegroundColor Yellow }

try {
    # 'stop'/'status' don't launch OBS if it's not up; 'start'/'toggle' do.
    if ($Action -in 'start', 'toggle') {
        $state = Start-OBSIfNeeded -Port $Port
        if ($state -eq 'started') { Write-Info 'Started OBS (minimized to tray)...' ; Start-Sleep -Seconds 2 }
    }
    else {
        if (-not (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)) {
            Write-Warn 'OBS is not running - nothing to do.'
            return
        }
    }

    $ws = Connect-OBS -Port $Port

    # Make sure capture sources + output settings exist (idempotent).
    if ($Action -in 'start', 'toggle') {
        Ensure-DisplayCapture $ws | Out-Null
        Ensure-GameCapture   $ws
        Ensure-AudioInputs   $ws
        Set-OBSRecordConfig  $ws -Directory $RecDir
    }

    $active = Get-OBSRecordActive $ws

    switch ($Action) {
        'status' {
            if ($active) {
                $st = (Invoke-OBSRequest $ws 'GetRecordStatus').responseData
                Write-Ok  ("RECORDING - {0} ({1:N0} MB so far)" -f $st.outputTimecode, ($st.outputBytes / 1MB))
            } else { Write-Info 'Idle (not recording).' }
            Write-Info ("Record folder: {0}" -f (Invoke-OBSRequest $ws 'GetRecordDirectory').responseData.recordDirectory)
        }
        'start' {
            if ($active) { Write-Warn 'Already recording.' }
            else { Start-OBSRecord $ws | Out-Null; Write-Ok 'Recording STARTED (native resolution @ 60fps, hardware encoder).' }
        }
        'stop' {
            if (-not $active) { Write-Warn 'Not currently recording.' }
            else {
                $out = Stop-OBSRecord $ws
                Start-Sleep -Milliseconds 800
                if ($out -and (Test-Path $out)) {
                    Write-Ok ("Saved: {0}  ({1:N1} MB)" -f $out, ((Get-Item $out).Length / 1MB))
                } else { Write-Ok ("Saved: {0}" -f $out) }
            }
        }
        'toggle' {
            if ($active) {
                $out = Stop-OBSRecord $ws
                Start-Sleep -Milliseconds 800
                if ($out -and (Test-Path $out)) {
                    Write-Ok ("Stopped. Saved: {0}  ({1:N1} MB)" -f $out, ((Get-Item $out).Length / 1MB))
                } else { Write-Ok ("Stopped. Saved: {0}" -f $out) }
            }
            else { Start-OBSRecord $ws | Out-Null; Write-Ok 'Recording STARTED (native resolution @ 60fps, hardware encoder).' }
        }
    }

    Disconnect-OBS $ws
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
