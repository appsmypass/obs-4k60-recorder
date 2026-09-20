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
- **[miccheck](https://github.com/appsmypass/miccheck)** — the audio half of
  the same problem. Finds the sample-rate mismatch that drifts your audio out
  of sync, a muted mic, and the Windows ducking setting that quietly drops your
  game audio by 80% whenever anything opens the microphone. Read-only.
- **[framecheck](https://github.com/appsmypass/framecheck)** — before you
  spend an evening editing, check the recording actually came out right. Finds
  variable framerate, duplicate frames, bitrate starvation and audio drift, and
  names the OBS setting behind each one. Read-only.
- **[diskrate](https://github.com/appsmypass/diskrate)** — framecheck tells
  you frames were dropped; this tells you whether the drive was why. Measures
  the worst single second of sustained write speed, not the peak, and defeats
  the Windows write cache — a naive benchmark overstated a real NVMe by 3.5x.
- **[gpucheck](https://github.com/appsmypass/gpucheck)** — on a laptop Windows
  silently decides which GPU each app gets, and sometimes gives one app both.
  Shows which adapter your game, OBS and browser are actually running on, and
  flags the process whose frames are being copied across the bus every frame.
  Read-only.
- **[cpuclock](https://github.com/appsmypass/cpuclock)** — Windows documents its
  own `CurrentClockSpeed` as unreliable, and it is: this laptop reports a 1498 MHz
  maximum while actually delivering 3493 MHz. Shows the real clock per core, and
  whether a cap is your power plan or the hardware. Read-only.
- **[ramcheck](https://github.com/appsmypass/ramcheck)** — Task Manager's
  `Memory 62%` tells you almost nothing. This shows the hard page faults that
  actually cause stutter, how much of that 62% is reclaimable cache, and your
  commit charge against the real limit — the number that decides whether the
  next alt-tab stalls. Read-only.
- **[netdrop](https://github.com/appsmypass/netdrop)** — OBS says
  "dropped frames (network)" and Task Manager's graph looks fine. Windows already
  measures the number that explains it — the TCP retransmission rate — and shows it
  in no UI at all. Also catches the stale Wi-Fi link speed: the status dialog said
  721 Mbps while the live counter said 400. Read-only.
- **[clipmine](https://github.com/appsmypass/clipmine)** — a three hour
  session usually has four things worth keeping. Scans the audio for the moments
  you got loud and cuts each one out as its own clip. Never touches the original.
- **[vidkit](https://github.com/appsmypass/vidkit)** — trim, compress and convert
  the recordings afterwards without memorising ffmpeg filtergraphs.
- **[dupefind](https://github.com/appsmypass/dupefind)** — three copies of the
  same clip across three drives is normal after a year. Finds byte-identical
  duplicates and sends the extras to the Recycle Bin, never a hard delete.
- **[pathfix](https://github.com/appsmypass/pathfix)** — "ffmpeg is not
  recognized" even though you installed it, or the wrong Python keeps running.
  Audits your PATH for broken folders and duplicates, and names which copy of a
  command actually wins. Dry run by default, with a journaled undo.
- **[bootlag](https://github.com/appsmypass/bootlag)** — your PC takes 50
  seconds to boot and Task Manager only says “High”. This reads Windows' own
  boot telemetry and gives you the millisecond cost of every startup app,
  service and boot phase, so you know what is actually worth disabling.
- **[diskscout](https://github.com/appsmypass/diskscout)** — 4K60 footage fills a
  drive fast; find what's eating it.
- **[truehz](https://github.com/appsmypass/truehz)** — your panel is not 60.000 Hz.
  It prints the exact refresh rational Windows rounds away, and tells you which
  capture fps actually matches it — often 30, not 60.
- **[audiodrift](https://github.com/appsmypass/audiodrift)** — truehz for sound.
  Measures the real sample rate of every audio endpoint from its own hardware
  clock, so you know which ones will drift apart over a long recording.
- **[timerlag](https://github.com/appsmypass/timerlag)** — your game asked
  Windows to wait 1 ms and got 15.6. Windows 11 silently ignores
  `timeBeginPeriod` for throttled processes and returns success anyway, so it
  measures the timer resolution your process actually receives.
- **[usbspeed](https://github.com/appsmypass/usbspeed)** — your capture card
  or external SSD is plugged into a 10 Gbps port and Windows still reports 480
  Mbps. Every Windows UI reads a field that stops at USB 3.0; this reads the one
  that does not, and was off by 20.8x on this laptop. Read-only.
- **[diskbusy](https://github.com/appsmypass/diskbusy)** — Task Manager
  says `Disk 100%` and it means almost nothing: that bar is a duty cycle, so it
  pins at 100% whether the drive is doing 500 IOPS or 500,000. This shows the
  number Windows hides — `% Disk Time` unclamped, which hit 730% here while
  each I/O still finished in 0.27 ms. Read-only.
- **[dpiscale](https://github.com/appsmypass/dpiscale)** — Settings
  says `Scale: 200%` and stops there. Windows quietly hands different
  resolutions to different apps depending on the DPI awareness each one
  declares, which is why display capture comes out the wrong size. Found this
  laptop driving a 3240x2160 panel at 1920x1080. Read-only.
- **[filelock](https://github.com/appsmypass/filelock)** — `The action
  can't be completed because the file is open in another program.` Windows
  knows exactly which program and refuses to say. This asks the Restart
  Manager — the API Windows Setup uses — and names the process, the PID and
  what to do about it. Never reports a locked file as free. Read-only.
- **[fragmap](https://github.com/appsmypass/fragmap)** — a recording that
  stutters on playback may simply be in thousands of pieces. `defrag /A`
  counts fragmented files across the whole drive but never names one, and
  Explorer shows only a size. This reads the NTFS extent map for a single
  file, counts the real physical fragments, and tells compression and sparse
  holes apart from genuine fragmentation. No elevation, read-only.
- **[codecmap](https://github.com/appsmypass/codecmap)** — OBS offers NVENC
  on one machine and only x264 on another, and nothing on screen explains
  why. This asks Media Foundation which codecs your GPUs can actually
  hardware-encode, asks Direct3D which ones they can hardware-decode, and
  shows both answers per GPU. Encoding and decoding are separate silicon,
  and this is where that difference becomes visible. No elevation,
  read-only.
- **[truefps](https://github.com/appsmypass/truefps)** — framecheck tells you
  a clip is variable frame rate; this tells you exactly how. It reads the
  MP4/MOV sample tables directly, rebuilds the true duration of every single
  frame, and reports real average fps, the longest stall in milliseconds,
  keyframe spacing and the audio/video duration drift that makes clips slide
  out of sync in an editor. Zero dependencies, read-only.

## License

MIT — see [LICENSE](LICENSE).
