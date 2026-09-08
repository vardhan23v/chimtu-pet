# Chimtu — a macOS desktop pet

[![Build & Release](https://github.com/vardhan23v/chimtu-pet/actions/workflows/release.yml/badge.svg)](https://github.com/vardhan23v/chimtu-pet/actions/workflows/release.yml)
[![Latest release](https://img.shields.io/github/v/release/vardhan23v/chimtu-pet?style=flat-square)](https://github.com/vardhan23v/chimtu-pet/releases/latest)

[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange?style=for-the-badge&logo=swift&logoColor=white)](https://www.swift.org/)
[![AppKit](https://img.shields.io/badge/AppKit-macOS-blue?style=for-the-badge&logo=apple&logoColor=white)](https://developer.apple.com/documentation/appkit)
[![Swift Package Manager](https://img.shields.io/badge/Swift%20Package%20Manager-supported-orange?style=for-the-badge&logo=swift&logoColor=white)](https://swift.org/package-manager/)
[![Python](https://img.shields.io/badge/Python-3.x-blue?style=for-the-badge&logo=python&logoColor=white)](https://www.python.org/)
[![Pillow](https://img.shields.io/badge/Assets-Pillow-green?style=for-the-badge&logo=python&logoColor=white)](https://python-pillow.org/)
[![macOS](https://img.shields.io/badge/macOS-13%2B-black?style=for-the-badge&logo=apple&logoColor=white)](https://www.apple.com/macos/)

Chimtu is a tiny, animated macOS desktop companion: a chubby Shiba named after
the Telugu internet meme, rendered as transparent sprite frames and living on
your screen. He idles, naps, follows your cursor, and reacts to what you do,
while using about 0.1% CPU.

> `Resources/peek.png` and `Resources/contact-sheet.png` are generated previews
> rather than tracked screenshots.
> They are intentionally ignored by Git; generate them locally with the asset
> command below when you want to inspect the artwork.

## Install

Grab the build for your machine from the [latest release](https://github.com/vardhan23v/chimtu-pet/releases/latest):

**macOS (Apple Silicon and Intel, universal binary)**

1. Download `Chimtu-macOS.zip`, unzip, and drag `Chimtu.app` into `/Applications`.
2. On first launch, right-click the app and choose **Open** (it is ad-hoc
   signed, not notarized). Chimtu then appears as 🐕 in the menu bar.

**Windows 10/11**

1. Download `Chimtu-Windows.zip` and unzip `Chimtu.exe` anywhere.
2. Run it. SmartScreen may ask once; choose **More info → Run anyway** (the
   exe is unsigned). Right-click Chimtu for his menu.

The Windows build (`windows/chimtu.py`, Tk + Python) shares the same sprite
frames and behaviours as the native macOS app: cursor-aware idle, click, hold,
drag, double-click, Follow Cursor, app-switch and low-battery reactions, and the
hourly howl. Run it from source with `python windows/chimtu.py` after rendering
the frames.

## Features

- Idle, sit, sleep, walk, run, scratch, yawn, wave, jump, dance, spin, shake,
  roll over, dig, sneeze, howl, eat, love, sniff, fetch, bark, beg, alert,
  happy, sad, and tired animations.
- Speech bubbles with short Telugu-meme lines, greetings, and the hourly time.
- Copy something and he sniffs it. Drop a file on him and he fetches it (opens it).
- Size menu: Small, Normal, Large, Huge. Sleeps longer between 11 pm and 6 am.
- Press and hold on Chimtu to pet him; he blushes.
- Howls on the hour (unless he is asleep). "Give Treat" makes him munch.
- Cursor-aware idle poses: Chimtu looks toward the mouse.
- Click to alternate between a wave and a happy wiggle; double-click to jump.
- Drag Chimtu to pick him up; he dangles, then lands with a squash.
- Reacts when you switch applications and greets you after the screen unlocks.
- Gets lonely after five minutes without mouse movement, then goes to sleep.
- Shows a tired animation when the Mac is on battery below 20%.
- Optional **Follow Cursor** mode, with smooth movement toward the pointer.
- Menu-bar controls for visibility, actions, cursor following, Launch at Login,
  and quitting.

## Menu-bar controls

Click Chimtu's 🐕 menu-bar icon to use:

| Action | What it does |
| --- | --- |
| Hide Chimtu / Show Chimtu | Toggle the pet window |
| Jump, Dance, Spin, Shake, Roll Over, Howl, Give Treat, Bark, Beg | Trigger an animation immediately |
| Size | Small / Normal / Large / Huge |
| Sit Down | Keep Chimtu seated for a while |
| Go to Sleep | Put Chimtu to sleep |
| Follow Cursor | Have Chimtu move toward and wait beside the pointer |
| Launch at Login | Register or unregister the app with macOS |
| Quit Chimtu | Exit the app |

The menu also shows the pointer and app-switch gestures. Chimtu has no Dock
icon and does not open a normal application window.

## Requirements

- macOS 13 or newer (universal: Apple Silicon and Intel), or Windows 10/11 for the Tk build
- Swift 5.9 or newer (Xcode or the macOS Command Line Tools)
- Python 3 with Pillow only when regenerating the sprite artwork

## Build and run

The repository includes a build script that creates a self-contained
`dist/Chimtu.app` bundle without requiring an Xcode project:

```sh
./build.sh
open dist/Chimtu.app
```

The script regenerates missing frames, builds the Swift executable in release
mode, copies the frames and icon into the app bundle, and applies an ad-hoc
signature when code signing is available. To remove the Swift build cache after
building:

```sh
./build.sh clean
```

For a compile-only check:

```sh
swift build -c release
```

## Architecture

Chimtu is a small Swift Package Manager executable built with AppKit:

- `AppDelegate` creates the status-bar menu and connects menu actions.
- `PetController` owns the animation state machine, movement, gestures,
  visibility, system-event reactions, and power-aware timing.
- `PetWindow` provides a borderless, transparent, floating window and a
  `CALayer`-backed view that swaps pre-decoded `CGImage` frames.
- `Sprites` loads the animation sequences from the app bundle.
- `main.swift` configures the app as an accessory (menu-bar-only) application.

## Battery behavior

The pet is designed to stay lightweight while idle:

- Animation frames are decoded once and swapped into a `CALayer`; Chimtu does
  not redraw the artwork every frame.
- Each animation uses one timer at its own frame rate, with tolerance so macOS
  can coalesce wakeups.
- The animation timer stops when Chimtu is hidden, the display or Mac sleeps,
  or the screen locks.
- Low Power Mode halves the animation frame rate.
- Cursor tracking samples the pointer on the existing animation tick. Follow
  Cursor adds a 60 Hz movement timer only while Chimtu is actively moving.

## Artwork and previews

The sprite artwork is generated procedurally with Pillow:

```sh
python3 -m pip install Pillow
python3 tools/render_sprites.py Resources/frames
```

The renderer writes the animation frames to `Resources/frames/` and creates:

- `Resources/contact-sheet.png` — all animation states in one sheet
- `Resources/peek.png` — a small preview of the idle frames

Those generated files, along with `dist/` and `.build/`, are ignored so source
control contains only the renderer and the app's source assets.

## Project layout

| Path | Purpose |
| --- | --- |
| `Sources/Chimtu/` | Swift AppKit application source |
| `Resources/Chimtu.icns` | Application icon |
| `tools/render_sprites.py` | Procedural sprite and preview generator |
| `Package.swift` | Swift Package Manager manifest |
| `Info.plist` | App bundle metadata and macOS behavior |
| `build.sh` | Release app-bundle build script (universal binary) |
| `windows/chimtu.py` | Windows port (Tk), packaged to `Chimtu.exe` by CI |

## Releases

Every push to `main` builds the app on GitHub Actions. Pushing a tag such as
`v1.3.0` publishes a GitHub Release with `Chimtu-macOS.zip` and
`Chimtu-Windows.zip` attached.

## License

MIT. See [LICENSE](LICENSE).
