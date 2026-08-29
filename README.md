# OBS 4K/60 Game Recorder

One-click **native-resolution 60fps game recorder for Windows** with **game audio + mic**.

It drives a genuine [OBS Studio](https://obsproject.com) install in the background
over its WebSocket API, using your **GPU hardware encoder** (NVIDIA NVENC by
default), and saves a single `.mp4` per session. You never have to touch the OBS
window — the scripts start it minimized to the tray and control it for you.

Built because Windows' `gdigrab`/GDI screen capture tops out around ~13fps at 4K —
real OBS + NVENC is what actually delivers smooth 4K60.

It **captures** your display at full native resolution but **encodes** a 1080p
copy by default, and it **closes OBS when you stop recording**. Both are
deliberate: see [Performance](#performance-if-games-feel-laggy).

You **start and stop it yourself** (before/after a game). No automatic
game-detection by design — you're in control.

## Requirements

- **Windows** with Windows PowerShell 5.1 (built in).
- **[OBS Studio](https://obsproject.com)** 28+ — either the normal installer or
  `scoop install obs-studio`. (obs-websocket is bundled with OBS.)
- A supported hardware encoder: **NVIDIA (NVENC)**, **Intel (QuickSync)**, or
  **AMD (AMF)**. Software `x264` also works on any GPU.

## Install

```powershell
git clone https://github.com/appsmypass/obs-4k60-recorder.git
cd obs-4k60-recorder
```

## First-time setup (run once)

Close OBS if it's open, then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\Setup-OBS.ps1
```

This creates an OBS profile + scene collection called **GameRec**, enables the
WebSocket server on `127.0.0.1:4455`, **auto-detects your primary monitor's
native resolution**, and encodes a downscaled 1080p/60 copy with NVENC. It also
turns OBS's live preview off and makes it start in the tray, so OBS isn't
re-rendering your whole screen in the background. Override anything:

```powershell
.\Setup-OBS.ps1 -OutputHeight 1440       # encode 1440p instead of 1080p
.\Setup-OBS.ps1 -OutputHeight 0          # encode at full native resolution
.\Setup-OBS.ps1 -Fps 30                  # 30fps instead of 60
.\Setup-OBS.ps1 -Width 1920 -Height 1080 # force the capture resolution
.\Setup-OBS.ps1 -Quality high            # bigger files, higher quality
.\Setup-OBS.ps1 -Encoder qsv             # Intel QuickSync
.\Setup-OBS.ps1 -Encoder amd             # AMD AMF
.\Setup-OBS.ps1 -Encoder x264            # software encode (any GPU)
.\Setup-OBS.ps1 -KeepPreview             # leave the OBS preview enabled
```

(Or just double-click `launcher\Setup.cmd`.)

Re-running setup is safe: it merges these settings into OBS's config files
instead of overwriting them, so your window layout and other OBS settings stay.

## Record

Double-click the launchers in `launcher\`, or run from a terminal:

| Launcher | Command | What it does |
|---|---|---|
| **Start-Recording.cmd** | `GameRec.ps1 start` | Starts OBS if needed, then begins recording. |
| **Stop-Recording.cmd** | `GameRec.ps1 stop` | Stops, saves the MP4 (prints the path), closes OBS. |
| **Toggle-Recording.cmd** | `GameRec.ps1 toggle` | Start if idle, stop+save if recording. |
| **Recording-Status.cmd** | `GameRec.ps1 status` | Shows recording state + output folder. |
| **Close-OBS.cmd** | `GameRec.ps1 quit` | Closes OBS so it stops using the GPU. |

Videos are saved to `%USERPROFILE%\Downloads\recordings\`, one MP4 per session:
H.264 (hardware-encoded) video + 48 kHz AAC stereo audio.

Useful switches:

```powershell
.\GameRec.ps1 start -Capture game    # hook the fullscreen game instead of the screen
.\GameRec.ps1 start -Capture both    # both sources (most GPU cost)
.\GameRec.ps1 stop  -KeepOpen        # leave OBS running after stopping
```

## What gets captured

- **Video:** your primary display (Display Capture). A Game Capture source for
  fullscreen games is also available via `-Capture game`, but only **one** capture
  source is active at a time — running both makes OBS capture the screen twice
  per frame for no extra footage.
- **Audio:** **Desktop Audio** (game/system sound) **and Mic**, mixed onto the
  recorded track. Created automatically so recordings are never silent.

## Performance (if games feel laggy)

OBS shares your GPU with the game, so the defaults are tuned to take as little
from it as possible:

- **Encode smaller than you capture.** Encoding full 4K60 at high quality
  saturates the NVENC block on most laptop/mid-range GPUs — OBS then drops frames
  ("skipped frames due to encoding lag") and produces a file with such a high
  bitrate that players stutter during playback. Capturing native and encoding
  1080p fixes both. Raise it with `-OutputHeight 1440` if your GPU has room.
- **`-Quality balanced` (default)** records at CQP 23. `-Quality high` is CQP 16,
  which is several times the bitrate and is the usual cause of "the recording
  plays back slower than the game did".
- **One capture source at a time** (see above).
- **Preview off, tray on.** An open OBS window re-renders your entire canvas
  continuously.
- **OBS is closed when you stop.** Even idle and minimized, OBS keeps capturing
  and compositing the canvas every frame. Use `-KeepOpen` to opt out, or
  `Close-OBS.cmd` to shut it down manually.

If a game still stutters, try `-OutputHeight 720`, then `-Fps 30`.

## How it works

```
GameRec.ps1  ──WebSocket──►  OBS Studio (tray)  ──NVENC──►  .mp4
     ▲                            ▲
 launcher\*.cmd            profile "GameRec" (Setup-OBS.ps1)
```

`OBS-Control.ps1` is a tiny obs-websocket 5.x client written in pure PowerShell
(no external modules). `GameRec.ps1` uses it to ensure the capture/audio sources
exist and to start/stop recording.

## Files

| File | Purpose |
|---|---|
| `Setup-OBS.ps1` | One-time OBS profile/scene/websocket configuration. |
| `GameRec.ps1` | Start / stop / toggle / status / quit control. |
| `OBS-Control.ps1` | obs-websocket client library. |
| `launcher\*.cmd` | Double-click launchers. |

## Troubleshooting

- **"OBS Studio not found"** — install it, then re-run `Setup-OBS.ps1`.
- **"websocket port never came up"** — in OBS: *Tools → WebSocket Server Settings
  → Enable*, port `4455`, no password (or re-run `Setup-OBS.ps1` with OBS closed).
- **Games stutter while recording** — see [Performance](#performance-if-games-feel-laggy).
- **Recordings play back choppily** — the file's bitrate is too high for your
  player. Re-run setup with a lower `-OutputHeight` and `-Quality balanced`.
- **No audio** — make sure a playback + mic device are set as *Default* in Windows
  Sound settings; the recorder uses the default devices.
- **Wrong monitor** — Display Capture picks the Primary monitor; set your game's
  screen as primary in Windows Display settings.
- **Settings don't seem to apply** — close OBS *before* running `Setup-OBS.ps1`;
  OBS rewrites its config files when it exits.

## License

MIT — see [LICENSE](LICENSE).
