# Chimtu v2 roadmap

## Context

Chimtu (work/chimtu-pet) reached v1.8 in three days: a native Swift/AppKit macOS pet (universal, ad-hoc signed, 2.2 MB, ~0.1% CPU idle), a Python+Tk Windows port packaged by PyInstaller, 43 procedurally rendered animation sets, and a long list of event-driven reactions. Everything lives in one 637-line `PetController.swift`, there are no tests, the only UI is the menu, and the Windows port hand-copies the state-machine weights (already drifting: its hourly howl is "every 3600 s", not on the hour).

You asked for a **focused 2–3 week v2** while caring about all of: polish & quality, a smarter pet, customization, Windows parity + Linux, and off-by-default sound. Those don't all fit in three weeks, so v2.0 takes the highest value-per-day slice of each and the rest is staged into 2.1 and 2.2 with reasons. Some items are blocked by things outside the code (Apple Developer account for notarization, a Windows signing service, Windows/Linux hardware for QA); the pipeline for those ships in 2.0 and activates when the blocker clears.

Non-negotiable throughout: the battery discipline. No new repeating timers (the only `repeats: true` timers stay the frame timer and the follow mover), everything reactive stays event-driven, and defaults never add cost.

## v2.0 scope (≈15 days, ships in 3 weeks)

| # | Item | Days |
| --- | --- | --- |
| A | Behaviour-preserving refactor into a testable core + `swift test` + `pytest` in CI | 3 |
| B | Memory across launches + mood/energy | 2.5 |
| C | Settings window | 2 |
| D | Sounds, off by default | 1.5 |
| E | Customization quick wins: 3 hats, 1 skin, editable phrases | 2 |
| F | Crash-proofing, notarization pipeline (secrets-gated), version from tag | 1.5 |
| G | Windows parity subset on a shared Python core | 1.5 |
| H | QA, battery before/after, release | 1 |

### A. Refactor (first, no behaviour change)

New layout:

```
Package.swift            → ChimtuCore (library, Foundation only) + Chimtu (exe) + ChimtuCoreTests
Sources/ChimtuCore/      Brain.swift, ReactionGate.swift, Mood.swift, PetState.swift, Phrases.swift, Behaviour.swift
Sources/Chimtu/          PetController.swift (thin), SystemObservers.swift, SoundPlayer.swift, SettingsWindow.swift, Preferences.swift, + existing files
Tests/ChimtuCoreTests/
windows/chimtu_core.py   mirrors ChimtuCore; windows/chimtu.py becomes UI only
tests/test_core.py       pytest; tests/fixtures/behaviour_vectors.json shared by both suites
```

Seams, extracted mechanically from `Sources/Chimtu/PetController.swift`:

- **Brain**: `chooseNextState()` becomes pure `Brain.chooseNext(ctx, rng) -> Decision`. `Context` carries current state, state age, focusActive, musicPlaying, userIdle, isNight, batteryLow, edge flags, mood. `Decision` is `.enter(state, duration, say:)`, `.walk(dir, duration)`, `.zoomies(dir)`. All `Double.random` calls move inside with an injected generator. Weight thresholds move to `Behaviour.weights` unchanged.
- **ReactionGate**: today's `react()` guards and `gestureActive` become a pure value, plus a `BurstCounter(window:)` that replaces the five copy-pasted timestamp filters (`petClickTimes`, `dragTimes`, `clickTimes`, `deleteTimes`, `keyTimes`).
- **SystemObservers**: `observeSystem()`, `watchDownloads()`, the key monitor, IOKit power callback, distributed notifications move out and emit a `SystemEvent` enum to a delegate. One shared observer set fans out to all pets (also fixes the per-friend duplicate observers). Takes a reaction mask so disabled categories are never registered.
- **Preferences**: one struct over `UserDefaults`, same keys (`hat`, `petScale`, `typingReactions`) so existing users keep settings.

Golden check before merging: run old and new next-state selection 100k times with a seeded RNG and identical contexts; state histograms must match within 0.5%.

Tests (minimal, valuable): Brain obligations order and weight distribution, night suppresses zoomies, low battery → tired; ReactionGate rate limit / force / held rules; BurstCounter thresholds (4-in-2s laugh, 8-in-5s shy, 3 drags pout, 6 deletes); Mood math and clamping; StateStore round-trip and corrupt-file quarantine; Phrases overlay. The Python suite asserts the same vectors against `chimtu_core.py`, which is what catches macOS/Windows drift.

CI (`.github/workflows/release.yml`): `swift test` before `./build.sh`; new `test-python` job on ubuntu that the `windows` job depends on; both required for tag builds.

### B. Memory + mood/energy

User-facing: launch greeting based on time away ("Missed you! (2 days)" after >8 h, "Back already?" otherwise), day streak, time-of-day greeting, lifetime totals in "How's your day?" plus `Mood 😊 Energy ▮▮▮▯▯`. Mood only re-weights the existing random table: low energy → more naps and yawns; high happiness → more dance and idle lines; low happiness (ignored for hours, dragged around) → occasional `sad` idles and curt lines. It never adds interruptions.

Model in `ChimtuCore/Mood.swift`: `happiness` (baseline 0.6, decays toward it with a 2 h time constant) and `energy` (+0.004/s asleep, −0.0006/s awake), integrated lazily whenever read; `MoodEvent`s (petted +0.08, treat +0.10, clicked +0.02, pouted −0.05, lonely −0.02, exertion −0.05 energy). Brain uses `sleepWeight = 0.12 + 0.25 × (1 − energy)`, `anticScale = 0.5 + happiness`, and `sad` idle with p=0.3 when happiness < 0.3.

Persistence in `ChimtuCore/PetState.swift`: versioned Codable `PetState` (mood, totals, firstLaunch, lastSeen, streak) at `~/Library/Application Support/Chimtu/state.json` (macOS) / `%APPDATA%\Chimtu\state.json` (Windows), atomic writes, corrupt file renamed to `.bad` and defaults used. Save on quit, Hide, suspend, and a one-shot 5-minute timer created only while dirty (tolerance 60 s). Call `disableSuddenTermination()` while dirty so `NSSupportsSuddenTermination` can stay on. Only the primary pet persists; friends read its mood at spawn. Replaces the in-memory `stats` tuple.

### C. Settings window

Menu gets **Settings… (⌘,)**. SwiftUI `SettingsView` in an `NSHostingController` inside a lazily created titled `NSWindow` (needs `NSApp.activate(ignoringOtherApps:)` since the app is `LSUIElement`). Tabs: General (Launch at Login, size slider, skin, hat, Follow Cursor, Typing Reactions with the Input Monitoring explanation), Behaviour (Chattiness Quiet/Normal/Chatty, Quiet hours replacing hard-coded `isNight`, per-category reaction toggles: app events, clipboard, downloads & drives, music, global clicks, hourly howl), Sound (enable, volume, preview), Stats (totals, streak, mood, Reset Chimtu), About (correct version). `Preferences: ObservableObject` posts a change notification; every controller re-applies (`apply(scale:)`, `setHat`, `setTypingReactions`, observers reconfigure). The menu keeps all current items and reads the same keys. No cost while closed.

### D. Sound

`tools/render_sounds.py` (stdlib `math`/`array`/`wave` only, so CI deps stay Pillow-only) synthesizes eight clips at 22.05 kHz mono, total <150 KB: bark, yip, awoo, sniff, snore, boing, chomp, ding. `build.sh` renders when `Resources/sounds` is empty and bundles them; `.gitignore` adds the folder. macOS `SoundPlayer.swift` preloads WAV `Data`, plays via a throwaway `AVAudioPlayer(data:)`, releases on finish; no engine, no persistent player. A static `[state: SoundID]` table in `enter()` triggers clips; reminders and focus-end play `ding`. Gate in Core: off by default, volume 0.3, never when suspended, in focus, in quiet hours, or within 6 s of the last clip; jump/land only when user-initiated. Windows uses `winsound.PlaySound(... SND_ASYNC)`. Battery: coreaudiod spins up ~2 s per clip; default-off keeps the idle claim intact.

### E. Customization quick wins

- Hats: add `beanie`, `bow`, `flower` to `draw_hat()` in `tools/render_sprites.py`; `Sprites.hat(_:)` unchanged; hat-hide list moves to `Behaviour.hatHiddenStates`.
- One extra skin: parametrize the palette (`SKINS = {"shiba": …, "cream": …}`), render to `Resources/frames/<skin>/`, `Sprites.load(skin:)` with fallback to shiba, only the selected skin decoded. About +1.5 MB per skin, so exactly one in 2.0.
- Phrases: all hard-coded lines (idle lines, bark/beg lines, love lines, reactions) move to bundled `Resources/phrases.json`; `Phrases.load(defaults:, user:)` overlays `~/Library/Application Support/Chimtu/phrases.json` by key, ignoring malformed files. Settings → "Edit Phrases…" writes the defaults there if absent and opens it. Windows reads the same format from `%APPDATA%\Chimtu`.

### F. Crash-proofing, notarization, versioning

Crash-proofing: `PetController.init?` guarding `idle`; store `let view: PetView` instead of the `as!` computed property; zoomies bounce uses `animations["run_right"] ?? current`; `Sprites.load` logs missing frames instead of silently truncating; focus half-way timer tracked and invalidated with the end timer; persistence and phrases fail soft.

Notarization pipeline (blocked on the $99 Apple Developer account, ships gated): `Chimtu.entitlements` (hardened runtime, no special entitlements); `build.sh` honours `SIGN_IDENTITY` (Developer ID sign with `--options runtime --timestamp`, else ad-hoc as today) and sets `CFBundleShortVersionString`/`CFBundleVersion` from `VERSION` (default `git describe --tags`) via PlistBuddy, fixing the app reporting "1.0". `release.yml` adds steps guarded by `if: secrets.APPLE_CERT_P12 != ''`: import p12 to a temp keychain, signed build, `notarytool submit --wait`, `stapler staple`, re-zip. Secrets: `APPLE_CERT_P12`, `APPLE_CERT_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`.

### G. Windows parity subset

Extract `windows/chimtu_core.py` (Brain, ReactionGate, BurstCounter, Mood, StateStore, Phrases) mirroring Swift; `chimtu.py` calls into it. Add hats (second canvas image, same hide list), size at 50%/100%/200% (`PhotoImage.zoom/subsample`; Tk is integer-only, README says so), on-the-hour howl, sounds, phrases, mood/persistence (prefs live under a `prefs` key in the same JSON), time-of-day greeting, lifetime stats. Zero new dependencies. Not in 2.0: tray icon, file drop, per-pixel alpha (all need a Win32 message pump; see 2.1).

## Deferred, and why

| Item | When | Reason |
| --- | --- | --- |
| Windows per-pixel alpha (`UpdateLayeredWindow` from a Pillow-composed DIB), tray icon, file drop | 2.1 | One 3-day ctypes spike; needs a Windows machine for QA |
| Signed Windows exe | 2.1 | Cost/process: OV/EV cert, Azure Trusted Signing, or SignPath (free for OSS, weeks to approve). Apply to SignPath now |
| Calendar awareness (EventKit) | 2.1 | New TCC permission + entitlement; do it after notarization is live; opt-in |
| More skins, outfits | 2.1 | ~1.5 MB per skin; outfits need per-pose anchors in the renderer |
| Persisted reminders, multi-monitor placement | 2.1 | Small but not core |
| Linux (GTK 4 + cairo RGBA on the shared Python core, X11 first, Wayland best-effort) | 2.2 | Tk can't do transparency on X11; Wayland/GNOME lacks global cursor and always-on-top |
| User sprite packs | 2.2 | Needs a format spec, validator, and error UI; largest new crash surface |
| Weather (Open-Meteo, typed city, opt-in) | 2.2 | Breaks the "no network" promise unless strictly opt-in |
| Notification awareness | never | No public API; reading the Notification Center DB needs Full Disk Access |
| Native Windows rewrite (C#/Rust) | not planned | Triplicates the state machine, months of work, and the real Windows complaints (jaggies, drop, hats, size, 12 MB) are fixable in Python |

## Critical files

- `work/chimtu-pet/Sources/Chimtu/PetController.swift` — source of every extraction; all 2.0 features hook `enter()`, `react()`, `chooseNextState()`, `say()`
- `work/chimtu-pet/Package.swift` — becomes library + exe + test target
- `work/chimtu-pet/windows/chimtu.py` — split into UI + `chimtu_core.py`
- `work/chimtu-pet/.github/workflows/release.yml` — test jobs, gated sign/notarize, sound rendering, zip-size gate
- `work/chimtu-pet/tools/render_sprites.py` — skin palettes, new hats; sibling `tools/render_sounds.py` follows its pattern
- `work/chimtu-pet/build.sh`, `Info.plist` — versioning and signing

Reuse: `react()`/`enter()`/`say()` as the only entry points for new behaviour; the pose-dictionary renderer for hats/skins; the existing "render if missing" pattern in `build.sh` for sounds; the CI workflow's two-job shape for the new test jobs.

## Verification

Manual QA per feature on macOS 13 and latest:

- Refactor: 30 min idle shows the same mix of poses; every gesture (click, double, hold, drag, 3 drags, 4 clicks, 8 clicks); app switch/launch/quit; short/long copy; new Downloads file; charger; dark mode; lock/unlock; Music and Spotify play/pause; focus start/halfway/end; reminder; hide → zero timers; friends follow hide/show.
- Memory/mood: totals survive relaunch; clock +2 days → "Missed you"; hand-corrupt `state.json` → fresh start and a `.bad` file; `kill -9` → last debounced save survives.
- Settings: every control round-trips; changes propagate to friends; a disabled reaction category really stops (clipboard off → nothing on copy); quiet hours override night; ⌘, brings the window to front.
- Sound: off on fresh install; on → clips at set volume; silent in focus, quiet hours, and within 6 s; off → no coreaudiod activity.
- Customization: hats hide in roll/spin/shake/sneeze/held; skin switch mid-animation doesn't crash; bad `phrases.json` → defaults, good → new lines.
- Crash-proofing/notarization: delete a frame from the bundle → still runs; `spctl -a -vv` accepted once signing is live; About shows the tag version.
- Windows: hats/size/sounds/persist; howl on the hour.

CI gates for tag builds: `swift test` green, `pytest` green with the shared vectors, both platform builds succeed, `lipo -archs` prints both arches, notarization Accepted when secrets exist, macOS zip < 6 MB.

Battery, same machine, v1.8 tag vs v2.0 RC: `top -stats wakeups` medians (idle ≤ 5/s, sleep ≤ 2/s, hidden ≈ 0); `powermetrics --show-process-energy` over 3 min with sound off and on; Activity Monitor 12-hr energy after a workday. A `CHIMTU_DEBUG_TIMERS=1` env var logs timer creation/invalidation so a leaked timer shows in Console. Publish the numbers in the README table.

## Milestones

| Milestone | Contents | Days | External blockers |
| --- | --- | --- | --- |
| 2.0 (3 weeks) | Items A–H above | ~15 | Apple Developer account for notarization to actually run |
| 2.1 (2 weeks) | Windows layered window + tray + file drop; Windows signing; EventKit calendar opt-in; 2 skins + first outfits; persisted reminders; multi-monitor | ~10 | Windows machine; signing service approval; notarization live |
| 2.2 (2–3 weeks) | Linux GTK port on the shared core; sprite-pack format + validator + import UI; weather opt-in; AppImage/Flatpak | ~12 | Linux X11 and Wayland test setups |

Suggested order inside 2.0: A → F (crash-proofing part) → B → C → E → D → G → H. A first so everything after it is covered by tests; sound late because it is independent and easy to cut if time runs short.
