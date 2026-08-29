<#
    GameRec.ps1  -  Manual game recorder (drives genuine OBS via websocket)

    USAGE:
        GameRec.ps1 start     # ensure OBS is running, then START recording
        GameRec.ps1 stop      # STOP recording, save the MP4, close OBS
        GameRec.ps1 toggle    # start if stopped, stop if recording
        GameRec.ps1 status    # show whether OBS is recording + record folder
        GameRec.ps1 quit      # close OBS so it stops using the GPU

    Captures your primary display at its native resolution and 60fps using your
    GPU hardware encoder (NVIDIA NVENC by default), with game sound + mic, to:
        %USERPROFILE%\Downloads\recordings\<date time>.mp4

    OBS is closed again after you stop, because it keeps capturing and rendering
    the canvas the whole time it is open - which costs GPU while you play. Pass
    -KeepOpen if you would rather leave it running between recordings.

    You start/stop it yourself (e.g. before/after a game). No auto game-detection.

    First-time setup: run Setup-OBS.ps1 once (configures the OBS profile + enables
    the websocket server this script talks to).
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('start', 'stop', 'toggle', 'status', 'quit')]
    [string]$Action = 'toggle',
    # 'display' is cheapest. 'game' hooks fullscreen games only. 'both' costs the most.
    [ValidateSet('display', 'game', 'both')]
    [string]$Capture = 'display',
    # Leave OBS running after stopping a recording.
    [switch]$KeepOpen,
    [int]$Port = 4455
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'OBS-Control.ps1')

$RecDir = "$env:USERPROFILE\Downloads\recordings"

function Write-Info($m) { Write-Host $m -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host $m -ForegroundColor Green }
function Write-Warn($m) { Write-Host $m -ForegroundColor Yellow }

function Complete-Recording {
    param($Ws, [string]$Prefix = 'Saved')
    $out = Stop-OBSRecord $Ws
    Wait-OBSRecordStopped $Ws | Out-Null
    Start-Sleep -Milliseconds 800
    if ($out -and (Test-Path $out)) {
        Write-Ok ("{0}: {1}  ({2:N1} MB)" -f $Prefix, $out, ((Get-Item $out).Length / 1MB))
    } else {
        Write-Ok ("{0}: {1}" -f $Prefix, $out)
    }
}

try {
    # 'stop'/'status'/'quit' don't launch OBS if it's not up; 'start'/'toggle' do.
    if ($Action -in 'start', 'toggle') {
        $state = Start-OBSIfNeeded -Port $Port
        if ($state -eq 'started') { Write-Info 'Started OBS (minimized to tray)...' ; Start-Sleep -Seconds 2 }
    }
    else {
        if (-not (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)) {
            if ($Action -eq 'quit' -and (Get-Process obs64 -ErrorAction SilentlyContinue)) {
                if (Stop-OBSStudio) { Write-Ok 'Closed OBS.' } else { Write-Warn 'Could not close OBS.' }
                return
            }
            Write-Warn 'OBS is not running - nothing to do.'
            return
        }
    }

    if ($Action -eq 'quit') {
        $ws = Connect-OBS -Port $Port
        if (Get-OBSRecordActive $ws) { Complete-Recording $ws -Prefix 'Stopped, saved' }
        Disconnect-OBS $ws
        if (Stop-OBSStudio) { Write-Ok 'Closed OBS.' } else { Write-Warn 'Could not close OBS.' }
        return
    }

    $ws = Connect-OBS -Port $Port

    $active = Get-OBSRecordActive $ws
    $willStart = -not $active -and $Action -in 'start', 'toggle'

    # Only touch sources/output settings when a recording is about to begin. OBS
    # rejects SetRecordDirectory while a recording is running, and reconfiguring
    # capture sources mid-recording would show up in the footage.
    if ($willStart) {
        Set-OBSCaptureMode   $ws -Mode $Capture
        Ensure-AudioInputs   $ws
        Set-OBSRecordConfig  $ws -Directory $RecDir
    }

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
            else { Start-OBSRecord $ws | Out-Null; Write-Ok 'Recording STARTED (hardware encoder).' }
        }
        'stop' {
            if (-not $active) { Write-Warn 'Not currently recording.' }
            else { Complete-Recording $ws }
        }
        'toggle' {
            if ($active) { Complete-Recording $ws -Prefix 'Stopped. Saved' }
            else { Start-OBSRecord $ws | Out-Null; Write-Ok 'Recording STARTED (hardware encoder).' }
        }
    }

    $stoppedRecording = ($Action -eq 'stop' -and $active) -or ($Action -eq 'toggle' -and $active)
    Disconnect-OBS $ws

    if ($stoppedRecording -and -not $KeepOpen) {
        if (Stop-OBSStudio) { Write-Info 'Closed OBS (it no longer uses the GPU).' }
    }
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
