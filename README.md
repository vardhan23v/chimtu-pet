<h1 align="center">🐕 Chimtu</h1>
<p align="center"><b>A tiny Shiba desktop pet that lives on your screen and reacts to what you do.</b><br>
Named after the Telugu internet meme. Native on macOS, ported to Windows. ~0.1% CPU.</p>

<p align="center">
  <a href="https://github.com/vardhan23v/chimtu-pet/actions/workflows/release.yml"><img alt="Build & Release" src="https://img.shields.io/github/actions/workflow/status/vardhan23v/chimtu-pet/release.yml?branch=main&style=for-the-badge&logo=githubactions&logoColor=white&label=build"></a>
  <a href="https://github.com/vardhan23v/chimtu-pet/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/vardhan23v/chimtu-pet?style=for-the-badge&logo=github&label=release&color=e08a3a"></a>
  <a href="https://github.com/vardhan23v/chimtu-pet/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/vardhan23v/chimtu-pet/total?style=for-the-badge&logo=github&color=4c9a2a"></a>
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-blue?style=for-the-badge"></a>
</p>
<p align="center">
  <img alt="macOS 13+ universal" src="https://img.shields.io/badge/macOS-13%2B%20%C2%B7%20Apple%20Silicon%20%2B%20Intel-000000?style=flat-square&logo=apple&logoColor=white">
  <img alt="Windows 10/11" src="https://img.shields.io/badge/Windows-10%20%2F%2011-0078D4?style=flat-square&logo=windows&logoColor=white">
  <img alt="Swift 5.9" src="https://img.shields.io/badge/Swift-5.9%20%C2%B7%20AppKit-F05138?style=flat-square&logo=swift&logoColor=white">
  <img alt="Python 3.12 Tk" src="https://img.shields.io/badge/Python-3.12%20%C2%B7%20Tk-3776AB?style=flat-square&logo=python&logoColor=white">
  <img alt="43 animations" src="https://img.shields.io/badge/animations-43-ff6f91?style=flat-square">
  <img alt="Idle CPU" src="https://img.shields.io/badge/idle%20CPU-~0.1%25-brightgreen?style=flat-square">
  <img alt="App size" src="https://img.shields.io/badge/macOS%20app-2.2%20MB-lightgrey?style=flat-square">
</p>

<p align="center"><img src="docs/preview.png" alt="Chimtu in a few of his moods" width="672"></p>

## Install

Download from the [latest release](https://github.com/vardhan23v/chimtu-pet/releases/latest).

| Platform | File | Steps |
| --- | --- | --- |
| macOS 13+ (Apple Silicon and Intel, one universal binary) | `Chimtu-macOS.zip` | Unzip, drag `Chimtu.app` to `/Applications`. First launch: right-click → **Open** (ad-hoc signed, not notarized). He appears as 🐕 in the menu bar. |
| Windows 10 / 11 | `Chimtu-Windows.zip` | Unzip `Chimtu.exe` anywhere and run it. SmartScreen may ask once: **More info → Run anyway** (unsigned). Right-click Chimtu for his menu. |

Optional on macOS: **Typing Reactions** needs Input Monitoring (System Settings → Privacy & Security). Chimtu only counts keystrokes; he never reads them.

## What he does on his own

| Mood | Animations |
| --- | --- |
| Resting | idle (eyes follow your cursor), sit, sleep, yawn, stretch, tired (battery < 20%), sad → nap (5 min without you) |
| Moving | walk, run, jump, zoomies (sprints across the screen), roll over, spin, chase tail |
| Antics | scratch, shake, dance, dig, sneeze, hiccup, wink, howl on the hour, bark, beg |
| Feelings | happy, love, laugh, pout, peek (shy), alert, celebrate, groove, focus, think, salute |
| Props | eat (treat), fetch (paper), typing (tap-tap), hats: party hat · cap · crown |

He also chats in small speech bubbles: "Bow bow!", "Em chestunnav?", "Treat unda?", "Hi hooman", greetings, and the time when he howls. Between 11 pm and 6 am he mostly sleeps.

## How he reacts to you

| You do this | Chimtu does this |
| --- | --- |
| Click him | waves, then a happy wiggle (alternating) |
| Four quick clicks | laughs: "Hehehe, tickles!" |
| Eight clicks in five seconds | hides behind his paws: "Shy!" |
| Double-click | jumps |
| Press and hold | blushes: ❤️ |
| Drag him | dangles while held, lands with a squash |
| Drag him three times in a row | pouts: "Hey! Put me down" |
| Drop a file on him (macOS) | fetches it, shows the name, opens it |
| Copy text | sniffs it; over 200 characters: thinks, "Hmm, long one" |
| Type steadily | taps along, "tak tak tak"; **Return** → hop "Sent!"; burst of deletes → "Oops?"; 10 min straight → "Break?" |
| Switch apps | perks up, often names the app |
| Open / quit an app (macOS) | "Ooh, Safari!" / waves or salutes "Bye Safari" |
| Click anywhere on screen (macOS) | glances toward it; six fast clicks → barks "Busy busy!" |
| Switch Spaces (macOS) | jumps "Whee!" |
| Plug/unplug a USB drive (macOS) | sniffs it / waves it off |
| New file in Downloads (macOS) | fetches it |
| Plug in the charger (macOS) | "Charging!" |
| Dark / light mode (macOS) | yawns "Night night" / "Bright!" |
| Play music in Music or Spotify (macOS) | grooves and shows the track |
| Unlock the screen | "Welcome back!" |

## Menu (🐕 in the menu bar · right-click on Windows)

| Item | What it does |
| --- | --- |
| Hide / Show Chimtu | toggle the pet (and his friends) |
| Jump, Dance, Spin, Shake, Roll Over, Howl, Give Treat, Bark, Beg, Zoomies, Stretch, Salute | play it now |
| Sit Down / Go to Sleep | park him for a while |
| Start Focus (25 min) | glasses on, halfway check-in, celebration at the end |
| Remind Me → 5 / 10 / 30 / 60 min | type a note; he barks it at you when it's time |
| How's your day? | winks and reports minutes together, pets, treats, keystrokes |
| Hat → None / Party Hat / Cap / Crown | dress him up (macOS) |
| Add a Friend | another Chimtu, up to four (macOS) |
| Size → Small / Normal / Large / Huge | remembered between launches (macOS) |
| Follow Cursor | he chases your pointer with smooth spring motion and waits beside it |
| Typing Reactions | on/off (macOS asks for Input Monitoring once) |
| Launch at Login | register with macOS |
| Quit Chimtu | bye |

## Why it barely touches the battery

- Frames are decoded once and swapped as `CALayer` contents. Nothing is drawn per frame.
- One timer per animation at its own rate (1–16 fps) with 50% tolerance so macOS coalesces wakeups.
- Timers are torn down when hidden, on display/system sleep, or screen lock. Low Power Mode halves the frame rate.
- Every reaction is event-driven (workspace notifications, a click monitor, a filesystem source on Downloads, IOKit power callbacks, player notifications). Nothing polls. The cursor, clipboard and idle timers piggyback on the animation tick.
- Follow Cursor runs a 60 Hz mover only while he is actually chasing.

Measured on an M-series MacBook Air: about 0.1% CPU idle, 11–35 MB RSS depending on how many frames are warm.

## Build from source

macOS (Command Line Tools are enough; no Xcode project):

```sh
./build.sh          # universal (arm64 + x86_64) dist/Chimtu.app
open dist/Chimtu.app
./build.sh clean    # also removes the Swift build caches
```

Windows / from source anywhere with Python 3.12:

```sh
python -m pip install pillow
python tools/render_sprites.py Resources/frames
python windows/chimtu.py
```

Sprites are drawn procedurally by `tools/render_sprites.py` (Pillow), so every pose is a few lines of code. It writes 256 palette-PNG frames, the hat overlays, a `contact-sheet.png` of all states and a `peek.png` preview; those are build products and are not tracked.

## Project layout

| Path | Purpose |
| --- | --- |
| `Sources/Chimtu/` | Swift AppKit app: `AppDelegate` (menu), `PetController` (state machine, reactions, timers), `PetWindow` (transparent window, sprite/hat/bubble layers), `Sprites` (frame loader) |
| `windows/chimtu.py` | Windows port in Tk, packaged to `Chimtu.exe` by CI |
| `tools/render_sprites.py` | Procedural sprite renderer |
| `Resources/` | App icons; generated `frames/` at build time |
| `build.sh`, `Package.swift`, `Info.plist` | macOS build |
| `.github/workflows/release.yml` | CI: builds both platforms on every push; a `v*` tag publishes a GitHub Release with both zips |

## Releasing

```sh
git tag -a v1.9.0 -m "Chimtu 1.9.0" && git push origin v1.9.0
```

## License

MIT — see [LICENSE](LICENSE). The character is an original cartoon inspired by the Cheems / "Chimtu" meme; no third-party art is used.
