# NOTES-app: the Headroom menu bar app

Session: app. Branch: `cloud/app`. Owns `Sources/Headroom/*` and this file.

## Important: never compiled against AppKit

This sandbox is Linux. AppKit, CoreText, ServiceManagement and UserNotifications do not exist here,
so **this code has not been compiled for macOS or run even once**. What was checked:

1. `swiftc -parse` (Swift 5.10.1, Linux) on all eight files: no syntax errors.
2. A full `swiftc -typecheck` of all eight files against a hand-written stub file. The stub
   copies the macOS 13 SDK signatures I rely on (NSStatusItem, NSMenu, CGContext, CTLine,
   SMAppService, UNUserNotificationCenter, ...), plus the real `Model.swift` and stubs of the
   HeadroomCore/HeadroomMac API from OWNERSHIP.md. Result: no type errors. This catches mistakes
   in my own Swift (optionals, tuples, generics, labels). It does **not** prove the stubs match
   the real SDK. Three shims were needed only for Linux: `@objc`/`#selector` were rewritten
   (no ObjC runtime on Linux), and `NSMutableAttributedString()` was rewritten as
   `(string: "")` because Linux Foundation lacks the empty init. macOS has it.

First thing to do on a Mac: `swift build` then `swift run Headroom --demo`.

## What was built

| File | What it does |
|---|---|
| `main.swift` | `NSApplication.shared`, sets `AppDelegate`, `.accessory` policy, `run()`. |
| `AppDelegate.swift` | Owns the status item, the 2 s probe on a serial background queue, publishing to main, the 10 fps animation timer and its pause rules, accessibility label, tooltip, `--demo`. |
| `StatusView.swift` | The menu bar pill: `#030803` rounded rect (radius 5, inset 2pt top/bottom, 1 physical pixel `#00FF41` 30% border), rain clipped to the pill, then `AG 12  TTY 31  14.2G` and `+9`. Also `Palette`. |
| `MatrixRain.swift` | Deterministic rain engine shared by the pill and the menu header. |
| `MenuBuilder.swift` | `HeaderView` (320pt Matrix card with the big answer, memory bar, swap bar, pressure, per-agent estimate) and `MenuBuilder` (NSMenuDelegate that rebuilds the whole menu in `menuNeedsUpdate`). |
| `Settings.swift` | `AppSettings` (UserDefaults) and `DisplayMode`. |
| `Notifier.swift` | Danger notification, lazy authorization, 10 minute rate limit, skipped without a bundle id. |
| `LoginItem.swift` | `SMAppService.mainApp` wrapper, only when running from a `.app`. |

### Status item
- `NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)`, `autosaveName = "HeadroomStatusItem"`.
- `button.title = ""`, `StatusView` added as a subview of the button with `[.width, .height]` autoresizing. `hitTest` returns nil so every click reaches the button, which owns `statusItem.menu`.
- Width: the view computes its own preferred width from CTLine typographic widths and calls back; the delegate then sets `statusItem.length` to that number. So the item is created variable-length but in practice runs at an explicit length (that is the only way a custom subview gets a width; a button with an empty title would collapse).
- Height: whatever the button gets from the system (22-24pt classic, taller on notch Macs). Pill is `bounds.insetBy(dx: 1, dy: 2)`, text baseline is `pill.midY - capHeight/2` snapped to the backing pixel grid, so it is centered at any thickness.
- Segment text: `NSFont.monospacedSystemFont(ofSize: 11.5, weight: .bold)`. Labels `AG` and `TTY` at 60% green, numbers at 100%, glow via `CGContext.setShadow(blur: 3, color: green 80%)`. `+N` uses `kCTForegroundColorFromContextAttributeName` so its color (green / amber `#FFB000` / red `#FF3B30`) and the danger pulse (1.2 s cosine between 45% and 100% alpha) are set per frame without rebuilding text.
- Display modes: Full (`AG 12  TTY 31  14.2G  +9` over rain), Compact (`+9` only, over rain), Calm (full text, no rain; a 6 s rain burst plays when the level changes, which is my reading of "pause when the level is unchanged and the user picked Calm").
- Placeholder before the first scan: `AG --  TTY --  --.-G  +-`.

### Rain
- Columns every 7pt, rows 8.5pt, glyphs are half-width katakana U+FF66...U+FF9D plus 0-9 at 7.5pt monospaced.
- One CTLine per glyph (66 total) built once in a `static let`, with `kCTForegroundColorFromContextAttributeName = true`. A frame is `setFillColor(red:green:blue:alpha:)` + `CTLineDraw` per visible cell. No per-frame allocations: columns are a value array mutated in place, glyph choice is an integer hash of (column salt, row, frame/7), randomness is xorshift32.
- Head `#C8FFD4` at 70%; tail `#00FF41` from 35% fading towards 0 over 2-6 cells. Speeds 0.8-2.5 rows/s.
- The menu header uses the same engine (9pt columns, 55% intensity) and animates only while the menu is open.

### Animation and pause rules
- One `Timer` (target/selector, 0.1 s, tolerance 0.02) added to `RunLoop.main` in `.common` mode, so it also runs while the menu is tracking.
- The timer exists only while something moves: rain running in the pill, the danger pulse, or the header rain while the menu is open. Otherwise it is invalidated (zero wakeups).
- Rain is frozen (last frame stays drawn) under Low Power Mode (`ProcessInfo.isLowPowerModeEnabled`, re-evaluated on `.NSProcessInfoPowerStateDidChange`) and while screens sleep (`NSWorkspace.screensDidSleepNotification` / `screensDidWakeNotification`). Rain is hidden when disabled in settings or in Calm mode. The pulse also stops under low power / screen sleep (the `+N` stays solid red).
- On screen wake a fresh snapshot is requested immediately.

### Data
- `LiveProvider(settings:)` is created once; `snapshot()` runs every 2 s from a `DispatchSourceTimer` on a private serial queue (`qos: .utility`, 250 ms leeway), result hopped to main with `DispatchQueue.main.async`. The probes session documents LiveProvider as not thread safe; it is only ever touched on that one queue.
- Changing the reserve pushes the new `HeadroomSettings` into the provider on the same queue and rescans at once.
- `--demo`: no LiveProvider at all; `Fixtures.demo` is shown, with `headroomAgents` and `level` recomputed through `Estimator.headroom` / `Estimator.level` for the chosen reserve (so the Reserve submenu visibly does something in screenshots). Rain still animates. A "DEMO DATA (--demo)" row is shown in the menu.

### Menu (rebuilt every time it opens)
1. Header view: `+9 MORE AGENTS FIT` (`+1 MORE AGENT FITS` singular). Danger: `STOP. 0 MORE AGENTS FIT`; if danger was forced while the math still says N > 0, it reads `STOP. SWAP NEARLY FULL` (swap >= 85%) or `STOP. MEMORY CRITICAL` instead, because "STOP. 0 MORE" would contradict the `+N` shown in the bar. Memory bar: in use (dim green) | available minus reserve (green) | reserve (amber), with a `MEM 21.2G used 14.8G free 3.0G rsv` label. Swap bar colored green < 50% < amber < 85% < red. `PRESSURE NORMAL  41% FREE`. `1 agent ~ 280M (median of 12 running)` or `(default, none running)`.
2. AGENTS N: per kind, sorted by total memory: `Claude Code  x11  avg 280M  3.0G total`.
3. HEAVIEST SESSIONS: top 5 trees: `claude   ttys055  390M   7 procs`.
4. TERMINALS N: per app sorted by count, then `Total  31 sessions`.
5. Reserve: N GB (submenu 1/2/3/4/6/8, checkmark), Display: mode (submenu), Rain animation (checkmark), Launch at login (checkmark; "(needs Headroom.app)" and disabled when unbundled; "(approve in System Settings)" with a mixed state when `.requiresApproval`, clicking then opens Login Items settings), Notify when headroom hits 0 (default on; disabled with "(needs Headroom.app)" when unbundled).
6. Refresh now (Cmd-R), Copy snapshot JSON (Cmd-C, `Format.json`), Open Activity Monitor (by bundle id `com.apple.ActivityMonitor`, path fallback), Headroom on GitHub.
7. Quit Headroom (Cmd-Q).

### Notifications
- Fires when the level moves into `.danger` from anything else (including the first snapshot after launch), at most once per 600 s, only if "Notify" is on.
- Title `Headroom: no room for another agent`, body like `1.1G free, swap 92% used. Close an agent before starting a new one.` (swap part omitted when there is no swap).
- `requestAuthorization([.alert, .sound])` is called right before posting, so the permission prompt appears the first time it matters. Delegate `willPresent` returns `[.banner, .sound]`.
- `Bundle.main.bundleIdentifier == nil` (swift run) skips everything, because `UNUserNotificationCenter.current()` throws an ObjC exception without a bundle.

### Accessibility and tooltip
- `button.setAccessibilityLabel("12 agents, 31 terminals, 14.2 gigabytes free, 9 more agents fit")`, with singulars handled, "no more agents fit" at 0, and ". Memory is critical, do not start another agent" appended in danger. Gigabytes are GiB (`/ 2^30`), one decimal.
- The custom view returns `isAccessibilityElement() == false` so VoiceOver sees only the button.
- Tooltip: `Format.line(snapshot)` + newline + `Updated 14:03:22` (DateFormatter `.medium` time style, the snapshot's `takenAt`).

### Settings (UserDefaults, domain = bundle id, or the process name when unbundled)
`reserveGB` (Int, default 3), `displayMode` (`full`/`compact`/`calm`), `rainEnabled` (default true), `notifyOnDanger` (default true). Hidden: `defaultPerAgentMB` (Int) and `swapDangerRatio` (Double, 0-1] are read if present, e.g. `defaults write io.github.theluckystrike.headroom defaultPerAgentMB -int 400`.

## Assumptions

- `Fixtures.demo` is a static stored or computed property of type `Snapshot` (not a function) in HeadroomCore. If it is `Fixtures.demo()`, change one line in `AppDelegate.demoSnapshot()`.
- `Estimator.headroom(memory:perAgentBytes:settings:)` and `Estimator.level(headroom:memory:settings:)` exist exactly as in OWNERSHIP.md (only used in `--demo`).
- `Format.bytes` returns short strings like `14.2G` / `812M` (width of the pill depends on it; any length works).
- `LiveProvider` is `#if os(macOS)` in the probes branch (checked) and is not thread safe (handled).
- Ship's `Resources/Info.plist` (checked on `cloud/ship`) sets `LSUIElement` and bundle id `io.github.theluckystrike.headroom`. The app also calls `setActivationPolicy(.accessory)` itself so `swift run` gets no Dock icon either.
- Disabled `NSMenuItem`s with an `attributedTitle` that carries an explicit `.foregroundColor` keep that color (AppKit does not dim attributed titles). I believe this is true; if the info rows look grayed out, give them a no-op action instead.
- AppDelegate is implicitly `@MainActor` on recent SDKs because `NSApplicationDelegate` is. The package is Swift tools 5.9 (Swift 5 language mode), where cross-isolation issues are warnings, not errors. Work that runs on the probe queue is built by a free function (`probeJob`) so its closure is never inferred as main-actor isolated, and the power-state observer is `nonisolated` and hops to main.

## Must verify on a real Mac

1. **It compiles.** Likely spots if it does not: `main.swift` creating `AppDelegate()` from top-level code (should only warn in Swift 5 mode; if it errors under a newer compiler, wrap the four lines in `MainActor.assumeIsolated { }` or move them into an `@MainActor` static func); `@objc nonisolated private func powerStateChanged` (if the compiler rejects `nonisolated` there, just delete the word); `override func isAccessibilityElement() -> Bool`; the `userNotificationCenter(_:willPresent:withCompletionHandler:)` signature (newer SDKs mark the completion handler `@Sendable`; a mismatch is a warning and only matters while Headroom is frontmost).
2. **Halfwidth katakana render.** SF Mono has no katakana; I rely on CTLine font fallback (Hiragino). If cells come out empty, set the rain font to `NSFont(name: "HiraginoSans-W3", size: 7.5)`.
3. **Vertical centering** on a notch MacBook and a non-notch Mac, light and dark menu bar, and with "Reduce transparency" on. Check the pill does not touch the menu bar edges and that the `+N` glyph glow is not clipped (the pill clips the rain but not the text).
4. **Width behavior next to "never give up" (One Thing).** Item width changes when digits change (e.g. `+9` to `+10`); confirm neighbors shift without flicker. Cmd-drag reorder and that the position survives a relaunch (autosaveName).
5. **Click handling.** The subview's `hitTest` returns nil; confirm a click opens the menu and the button's own highlight does not look odd behind the pill.
6. **CPU.** Target < 1% on Apple silicon at 10 fps. Measure with `top -pid $(pgrep Headroom)` or Activity Monitor in Full mode and with the menu open. If it is over budget: drop the shadow on the main text, or cache the rain frame into a CGLayer and only redraw text.
7. **Timer stops.** In Calm mode with level ok and Rain off, the process should show ~0 wakeups (Activity Monitor > Energy, Idle Wake Ups).
8. **Low Power Mode and display sleep** actually freeze the rain.
9. **Menu header rain** animates while the menu is open (timer in `.common` mode, view redraw inside the menu window).
10. **Launch at login** from `build/Headroom.app` (ad-hoc signed). SMAppService may refuse or demand approval for ad-hoc signed apps outside /Applications; test from /Applications.
11. **Notifications** from the bundled app: prompt appears on first danger only; banner text; 10 minute limit. Easiest test: `defaults write io.github.theluckystrike.headroom swapDangerRatio -float 0.01` (any swap in use then forces danger), relaunch, and `defaults delete io.github.theluckystrike.headroom swapDangerRatio` afterwards. This assumes core's `Estimator.level` honors `swapDangerRatio` as Model.swift documents.
12. **`--demo`** for screenshots: `swift run Headroom --demo` (no notifications or login item there, by design) or `open build/Headroom.app --args --demo`.

## Known gaps

- No unit tests for the app target (UI only; the math lives in HeadroomCore).
- The danger title in the header can say `STOP. SWAP NEARLY FULL` while the pill still shows e.g. `+2` in red. That is the estimator's honest count; I kept the number rather than faking `+0`.
- The menu's info rows use system colors (labelColor) so they stay readable in light menus; only the header card is in the Matrix style.
- No "Preferences" window; everything lives in the menu. Hidden knobs need `defaults write`.
- Launch-at-login errors are shown with a modal NSAlert (activates the app). Fine for a rare error, not pretty.
- `statusItem.length` is set explicitly, so the item is effectively fixed-width between updates rather than `variableLength`.
- The rain uses `setFillColor(red:green:blue:alpha:)`, which is device RGB rather than sRGB; the difference from the exact hex values should be invisible at these alphas.
- No handling of multiple menu bars with different heights beyond what autoresizing gives (each screen gets its own replica of the status item, drawn by the same view code).
