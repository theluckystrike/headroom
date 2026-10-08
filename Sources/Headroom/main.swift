import AppKit

// Accessory app: no Dock icon, no main menu, lives in the menu bar only.
// Launch with `--demo` to show Fixtures.demo instead of live data (for screenshots).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
