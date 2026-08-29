<#
    OBS-Control.ps1  -  Minimal obs-websocket 5.x client for Windows PowerShell 5.1
    Dot-source this file, then use Connect-OBS / Invoke-OBSRequest / helpers.
    Used by GameRec.ps1 to start/stop OBS recordings over the websocket API.
#>

function Receive-OBSMessage {
    param($Ws, [int]$TimeoutSec = 20)
    $buffer = New-Object byte[] 131072
    $seg = [System.ArraySegment[byte]]::new($buffer)
    $ms = New-Object System.IO.MemoryStream
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    do {
        $task = $Ws.ReceiveAsync($seg, [System.Threading.CancellationToken]::None)
        while (-not $task.IsCompleted) {
            Start-Sleep -Milliseconds 15
            if ((Get-Date) -gt $deadline) { throw "OBS receive timeout after ${TimeoutSec}s" }
        }
        $res = $task.GetAwaiter().GetResult()
        if ($res.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { return $null }
        $ms.Write($buffer, 0, $res.Count)
    } while (-not $res.EndOfMessage)
    $json = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
    return ($json | ConvertFrom-Json)
}

function Send-OBSMessage {
    param($Ws, $Obj)
    $json = $Obj | ConvertTo-Json -Depth 25 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $seg = [System.ArraySegment[byte]]::new($bytes)
    $task = $Ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None)
    while (-not $task.IsCompleted) { Start-Sleep -Milliseconds 10 }
    $task.GetAwaiter().GetResult() | Out-Null
}

function Connect-OBS {
    param([int]$Port = 4455, [string]$Password = '')
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ws.Options.AddSubProtocol('obswebsocket.json')
    $uri = [Uri]("ws://127.0.0.1:$Port")
    $task = $ws.ConnectAsync($uri, [System.Threading.CancellationToken]::None)
    while (-not $task.IsCompleted) { Start-Sleep -Milliseconds 20 }
    $task.GetAwaiter().GetResult() | Out-Null

    $hello = Receive-OBSMessage $ws
    $identify = @{ op = 1; d = @{ rpcVersion = 1; eventSubscriptions = 0 } }
    if ($hello.d.authentication) {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $salt = $hello.d.authentication.salt
        $chal = $hello.d.authentication.challenge
        $secret = [Convert]::ToBase64String($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Password + $salt)))
        $authResp = [Convert]::ToBase64String($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($secret + $chal)))
        $identify.d.authentication = $authResp
    }
    Send-OBSMessage $ws $identify
    $ident = Receive-OBSMessage $ws
    if ($ident.op -ne 2) { throw "OBS Identify failed: $($ident | ConvertTo-Json -Compress)" }
    return $ws
}

function Invoke-OBSRequest {
    param($Ws, [string]$Type, $Data = @{})
    $id = [guid]::NewGuid().ToString()
    Send-OBSMessage $Ws @{ op = 6; d = @{ requestType = $Type; requestId = $id; requestData = $Data } }
    while ($true) {
        $m = Receive-OBSMessage $Ws
        if ($null -eq $m) { throw "OBS connection closed while awaiting '$Type'" }
        if ($m.op -eq 7 -and $m.d.requestId -eq $id) {
            if (-not $m.d.requestStatus.result) {
                throw "OBS request '$Type' failed: [$($m.d.requestStatus.code)] $($m.d.requestStatus.comment)"
            }
            return $m.d
        }
    }
}

function Disconnect-OBS {
    param($Ws)
    try {
        $task = $Ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'bye', [System.Threading.CancellationToken]::None)
        while (-not $task.IsCompleted) { Start-Sleep -Milliseconds 10 }
    } catch {}
    try { $Ws.Dispose() } catch {}
}

# ----- Convenience helpers -----

function Get-OBSInputs { param($Ws) (Invoke-OBSRequest $Ws 'GetInputList').responseData.inputs }

function Test-OBSInput {
    param($Ws, [string]$Name)
    [bool]((Get-OBSInputs $Ws) | Where-Object { $_.inputName -eq $Name })
}

function Ensure-DisplayCapture {
    param($Ws, [string]$Scene = 'Game', [string]$Name = 'Display Capture')
    if (-not (Test-OBSInput $Ws $Name)) {
        Invoke-OBSRequest $Ws 'CreateInput' @{
            sceneName = $Scene; inputName = $Name; inputKind = 'monitor_capture'
            inputSettings = @{ method = 2; capture_cursor = $true }; sceneItemEnabled = $true
        } | Out-Null
    }
    # Select the primary monitor (works across OBS versions: monitor_id or monitor).
    $prop = 'monitor_id'
    $items = @()
    try { $items = (Invoke-OBSRequest $Ws 'GetInputPropertiesListPropertyItems' @{ inputName = $Name; propertyName = 'monitor_id' }).responseData.propertyItems } catch {}
    if (-not $items -or $items.Count -eq 0) {
        $prop = 'monitor'
        try { $items = (Invoke-OBSRequest $Ws 'GetInputPropertiesListPropertyItems' @{ inputName = $Name; propertyName = 'monitor' }).responseData.propertyItems } catch {}
    }
    if ($items -and $items.Count -gt 0) {
        $pick = $items | Where-Object { $_.itemName -match 'Primary' } | Select-Object -First 1
        if (-not $pick) { $pick = $items | Select-Object -First 1 }
        $settings = @{ method = 2; capture_cursor = $true }
        $settings[$prop] = $pick.itemValue
        Invoke-OBSRequest $Ws 'SetInputSettings' @{ inputName = $Name; inputSettings = $settings } | Out-Null
        return $pick.itemName
    }
    return $null
}

function Ensure-GameCapture {
    param($Ws, [string]$Scene = 'Game', [string]$Name = 'Game Capture', [bool]$Enabled = $false)
    if (-not (Test-OBSInput $Ws $Name)) {
        Invoke-OBSRequest $Ws 'CreateInput' @{
            sceneName = $Scene; inputName = $Name; inputKind = 'game_capture'
            inputSettings = @{ capture_mode = 'any_fullscreen'; capture_cursor = $true; anti_cheat_hook = $true }
            sceneItemEnabled = $Enabled
        } | Out-Null
    }
}

function Get-OBSSceneItemId {
    param($Ws, [string]$Scene = 'Game', [string]$Source)
    try { return (Invoke-OBSRequest $Ws 'GetSceneItemId' @{ sceneName = $Scene; sourceName = $Source }).responseData.sceneItemId }
    catch { return $null }
}

function Set-OBSSceneItemEnabled {
    param($Ws, [string]$Scene = 'Game', [string]$Source, [bool]$Enabled)
    $id = Get-OBSSceneItemId $Ws -Scene $Scene -Source $Source
    if ($null -eq $id) { return $false }
    try {
        Invoke-OBSRequest $Ws 'SetSceneItemEnabled' @{ sceneName = $Scene; sceneItemId = $id; sceneItemEnabled = $Enabled } | Out-Null
        return $true
    } catch { return $false }
}

function Set-OBSCaptureMode {
    <#
        Keeps exactly one capture source live. Running Display Capture and Game
        Capture together makes OBS capture and composite the screen twice every
        frame, which is a large GPU cost during gameplay for no extra footage.
        A hidden source goes inactive, so OBS stops capturing it entirely.
    #>
    param($Ws, [ValidateSet('display', 'game', 'both')][string]$Mode = 'display', [string]$Scene = 'Game')
    switch ($Mode) {
        'display' {
            Ensure-DisplayCapture $Ws -Scene $Scene | Out-Null
            Set-OBSSceneItemEnabled $Ws -Scene $Scene -Source 'Display Capture' -Enabled $true  | Out-Null
            Set-OBSSceneItemEnabled $Ws -Scene $Scene -Source 'Game Capture'    -Enabled $false | Out-Null
        }
        'game' {
            Ensure-GameCapture $Ws -Scene $Scene -Enabled $true
            Set-OBSSceneItemEnabled $Ws -Scene $Scene -Source 'Game Capture'    -Enabled $true  | Out-Null
            Set-OBSSceneItemEnabled $Ws -Scene $Scene -Source 'Display Capture' -Enabled $false | Out-Null
        }
        'both' {
            Ensure-DisplayCapture $Ws -Scene $Scene | Out-Null
            Ensure-GameCapture $Ws -Scene $Scene -Enabled $true
            Set-OBSSceneItemEnabled $Ws -Scene $Scene -Source 'Display Capture' -Enabled $true | Out-Null
            Set-OBSSceneItemEnabled $Ws -Scene $Scene -Source 'Game Capture'    -Enabled $true | Out-Null
        }
    }
}

function Ensure-AudioInputs {
    # Guarantees a Desktop Audio (game/system sound) + Mic source exist and are
    # routed to record track 1. Without this the MP4 has a silent audio track.
    param($Ws, [string]$Scene = 'Game')
    $map = @(
        @{ Name = 'Desktop Audio'; Kind = 'wasapi_output_capture' },
        @{ Name = 'Mic';           Kind = 'wasapi_input_capture'  }
    )
    foreach ($a in $map) {
        if (-not (Test-OBSInput $Ws $a.Name)) {
            Invoke-OBSRequest $Ws 'CreateInput' @{
                sceneName = $Scene; inputName = $a.Name; inputKind = $a.Kind
                inputSettings = @{ device_id = 'default' }; sceneItemEnabled = $true
            } | Out-Null
        }
        # Always (re)assert routing onto track 1
        try { Invoke-OBSRequest $Ws 'SetInputAudioTracks' @{ inputName = $a.Name; inputAudioTracks = @{ '1' = $true } } | Out-Null } catch {}
    }
}

function Set-OBSRecordConfig {
    param($Ws, [string]$Directory, [string]$FilenameFormat = '%CCYY-%MM-%DD %hh-%mm-%ss')
    # OBS rejects these while a recording is running; they are also only a
    # convenience (the profile already points at the same folder), so a failure
    # here must never stop the caller from starting or stopping a recording.
    if (Get-OBSRecordActive $Ws) { return }
    if ($Directory) {
        if (-not (Test-Path $Directory)) { New-Item -ItemType Directory -Force -Path $Directory | Out-Null }
        try { Invoke-OBSRequest $Ws 'SetRecordDirectory' @{ recordDirectory = $Directory } | Out-Null }
        catch { Write-Warning "Could not set record directory: $($_.Exception.Message)" }
    }
    try { Invoke-OBSRequest $Ws 'SetProfileParameter' @{ parameterCategory = 'Output'; parameterName = 'FilenameFormatting'; parameterValue = $FilenameFormat } | Out-Null }
    catch { Write-Warning "Could not set filename format: $($_.Exception.Message)" }
}

function Get-OBSRecordActive { param($Ws) [bool](Invoke-OBSRequest $Ws 'GetRecordStatus').responseData.outputActive }

function Start-OBSRecord {
    param($Ws)
    if (-not (Get-OBSRecordActive $Ws)) { Invoke-OBSRequest $Ws 'StartRecord' | Out-Null; return $true }
    return $false
}

function Stop-OBSRecord {
    param($Ws)
    if (Get-OBSRecordActive $Ws) { return (Invoke-OBSRequest $Ws 'StopRecord').responseData.outputPath }
    return $null
}

function Wait-OBSRecordStopped {
    # The MP4 is still being finalized for a moment after StopRecord returns.
    param($Ws, [int]$TimeoutSec = 30)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try { if (-not (Get-OBSRecordActive $Ws)) { return $true } } catch { return $true }
        Start-Sleep -Milliseconds 250
    }
    return $false
}

function Stop-OBSStudio {
    <#
        Closes OBS so it stops rendering the scene while you play. OBS keeps
        capturing and compositing the canvas the whole time it is open, even when
        idle and minimized, so leaving it running costs GPU during gameplay.
        Only call this once recording has fully stopped.
    #>
    param([int]$TimeoutSec = 20)
    $procs = @(Get-Process obs64 -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { return $false }

    foreach ($p in $procs) {
        try { if ($p.MainWindowHandle -ne 0) { $p.CloseMainWindow() | Out-Null } } catch {}
    }
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-Process obs64 -ErrorAction SilentlyContinue)) { return $true }
        Start-Sleep -Milliseconds 300
    }
    # Minimized to tray there is no window to close, so ask the process to exit.
    foreach ($p in @(Get-Process obs64 -ErrorAction SilentlyContinue)) {
        try { Stop-Process -Id $p.Id -ErrorAction SilentlyContinue } catch {}
    }
    Start-Sleep -Milliseconds 500
    return (-not (Get-Process obs64 -ErrorAction SilentlyContinue))
}

function Get-OBSStudioPath {
    # Returns the folder containing obs64.exe, searching common install locations.
    $candidates = @(
        "$env:USERPROFILE\scoop\apps\obs-studio\current\bin\64bit",
        "$env:ProgramFiles\obs-studio\bin\64bit",
        "${env:ProgramFiles(x86)}\obs-studio\bin\64bit"
    )
    foreach ($c in $candidates) { if ($c -and (Test-Path (Join-Path $c 'obs64.exe'))) { return $c } }
    return $null
}

function Start-OBSIfNeeded {
    param([int]$Port = 4455, [int]$TimeoutSec = 40, [string]$Profile = 'GameRec', [string]$Collection = 'GameRec')
    $running = Get-Process obs64 -ErrorAction SilentlyContinue
    $portUp  = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($running -and $portUp) { return 'already-running' }

    if (-not $running) {
        $bin = Get-OBSStudioPath
        if (-not $bin) { throw "OBS Studio not found. Install it (https://obsproject.com or 'scoop install obs-studio') and run Setup-OBS.ps1." }
        $obs = Join-Path $bin 'obs64.exe'
        Start-Process -FilePath $obs -WorkingDirectory $bin `
            -ArgumentList '--minimize-to-tray','--disable-shutdown-check','--collection',$Collection,'--profile',$Profile | Out-Null
    }
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) { Start-Sleep -Milliseconds 500; return 'started' }
        Start-Sleep -Milliseconds 500
    }
    throw "OBS started but websocket port $Port never came up within ${TimeoutSec}s. Enable it in OBS: Tools > WebSocket Server Settings."
}
