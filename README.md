# Chimtu — a macOS desktop pet

Chimtu is the Telugu-meme Cheems Shiba, living at the bottom of your screen.
He idles, sits, naps, wanders a little, and waves when you click him.
Menu-bar icon 🐕 lets you hide/show or quit him.

## Build & run

```sh
./build.sh          # needs only the Swift toolchain (Command Line Tools)
open dist/Chimtu.app
```

## Why it is easy on the battery

- No Dock icon, no windows besides the transparent pet layer (`LSUIElement`).
- Frames are pre-decoded PNGs swapped in as `CALayer.contents`; nothing is drawn per frame.
- One `Timer` at the animation's own rate (1–8 fps) with 50% tolerance so macOS can coalesce wakeups.
- The timer is torn down when the pet is hidden, the display sleeps, the Mac sleeps, or the screen locks.
- Low Power Mode halves the frame rate automatically.
- Measured: ~0.1% CPU while idle, ~12 MB RSS.

## Art

`tools/render_sprites.py` draws every frame procedurally (Pillow). Re-run it and
`./build.sh` to change the look. `Resources/contact-sheet.png` previews all states.
