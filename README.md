# Chimtu — a macOS desktop pet

Chimtu is the Telugu-meme Cheems Shiba, living at the bottom of your screen.
He idles, sits, naps, wanders a little, scratches an ear, and yawns when he
wakes up. His eyes follow your cursor. Click him to wave or wiggle, double-click to jump.
He perks up and looks around when you switch apps, and greets you when you unlock the screen.
Menu-bar icon 🐕: Hide/Show, Jump, Sit Down, Go to Sleep, Follow Cursor, Launch at Login, Quit.
Follow Cursor makes him trot after your mouse anywhere on screen and wait beside it.

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
- Cursor tracking reads the mouse position on the existing tick, never via an event monitor.
- Measured: ~0.1% CPU while idle, ~13 MB RSS.

## Art

`tools/render_sprites.py` draws every frame procedurally (Pillow). Re-run it and
`./build.sh` to change the look. `Resources/contact-sheet.png` previews all states.
