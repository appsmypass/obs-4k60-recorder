# OBS 4K/60 Game Recorder

One-click **4K / 60fps game recorder for Windows** with **game audio + mic**.

It drives a genuine [OBS Studio](https://obsproject.com) install in the background
over its WebSocket API, using your **GPU hardware encoder** (NVIDIA NVENC by
default), and saves a single `.mp4` per session. You never have to touch the OBS
window — the scripts start it minimized to the tray and control it for you.

Built because Windows' `gdigrab`/GDI screen capture tops out around ~13fps at 4K —
real OBS + NVENC is what actually delivers smooth 4K60.

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
WebSocket server on `127.0.0.1:4455`, and **auto-detects your primary monitor's
native resolution** at 60fps with NVENC. Override anything:

```powershell
.\Setup-OBS.ps1 -Fps 30                  # 30fps instead of 60
.\Setup-OBS.ps1 -Width 1920 -Height 1080 # force a resolution
.\Setup-OBS.ps1 -Encoder qsv             # Intel QuickSync
.\Setup-OBS.ps1 -Encoder amd             # AMD AMF
.\Setup-OBS.ps1 -Encoder x264            # software encode (any GPU)
```

(Or just double-click `launcher\Setup.cmd`.)

## Record

Double-click the launchers in `launcher\`, or run from a terminal:

| Launcher | Command | What it does |
|---|---|---|
| **Start-Recording.cmd** | `GameRec.ps1 start` | Starts OBS if needed, then begins recording. |
| **Stop-Recording.cmd** | `GameRec.ps1 stop` | Stops and saves the MP4 (prints the path). |
| **Toggle-Recording.cmd** | `GameRec.ps1 toggle` | Start if idle, stop+save if recording. |
| **Recording-Status.cmd** | `GameRec.ps1 status` | Shows recording state + output folder. |

Videos are saved to `%USERPROFILE%\Downloads\recordings\`, one MP4 per session:
H.264 (hardware-encoded) video + 48 kHz AAC stereo audio.

## What gets captured

- **Video:** your primary display (Display Capture) plus a Game Capture source for
  fullscreen games. Both live in the `Game` scene.
- **Audio:** **Desktop Audio** (game/system sound) **and Mic**, mixed onto the
  recorded track. Created automatically so recordings are never silent.

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
| `GameRec.ps1` | Start / stop / toggle / status control. |
| `OBS-Control.ps1` | obs-websocket client library. |
| `launcher\*.cmd` | Double-click launchers. |

## Troubleshooting

- **"OBS Studio not found"** — install it, then re-run `Setup-OBS.ps1`.
- **"websocket port never came up"** — in OBS: *Tools → WebSocket Server Settings
  → Enable*, port `4455`, no password (or re-run `Setup-OBS.ps1` with OBS closed).
- **No audio** — make sure a playback + mic device are set as *Default* in Windows
  Sound settings; the recorder uses the default devices.
- **Wrong monitor** — Display Capture picks the Primary monitor; set your game's
  screen as primary in Windows Display settings.

## See also

Recording at 4K60 is only half the job — the other half is having the headroom to
actually play well while it happens.

- **[gamemode](https://github.com/appsmypass/gamemode)** — one command to close
  background bloat, pause Windows Update/Search indexing and switch power plans
  before you record, and one command to put it all back afterwards. It knows not
  to touch a running OBS or ffmpeg process.
- **[clipsort](https://github.com/appsmypass/clipsort)** — after a month of
  recording you will have hundreds of files called `2026-09-08 14-22-11.mkv`.
  This sorts them into `Game\YYYY-MM\` folders, and knows to leave a clip alone
  while OBS is still writing to it.
- **[vidkit](https://github.com/appsmypass/vidkit)** — trim, compress and convert
  the recordings afterwards without memorising ffmpeg filtergraphs.
- **[dupefind](https://github.com/appsmypass/dupefind)** — three copies of the
  same clip across three drives is normal after a year. Finds byte-identical
  duplicates and sends the extras to the Recycle Bin, never a hard delete.
- **[diskscout](https://github.com/appsmypass/diskscout)** — 4K60 footage fills a
  drive fast; find what's eating it.

## License

MIT — see [LICENSE](LICENSE).
