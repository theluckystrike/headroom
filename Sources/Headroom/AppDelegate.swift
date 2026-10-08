import AppKit
import HeadroomCore
import HeadroomMac

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let probeInterval: DispatchTimeInterval = .seconds(2)
    static let frameInterval: TimeInterval = 0.1 // 10 fps
    static let calmBurstDuration: TimeInterval = 6

    let settings = AppSettings()
    let isDemo = CommandLine.arguments.contains("--demo")
    private(set) var snapshot: Snapshot?

    private var statusItem: NSStatusItem!
    private var statusView: StatusView!
    private var menuBuilder: MenuBuilder!
    private let notifier = Notifier()

    /// LiveProvider is only touched on `probeQueue`.
    private let probeQueue = DispatchQueue(label: "com.headroom.probe", qos: .utility)
    private var provider: LiveProvider?
    private var probeTimer: DispatchSourceTimer?

    private var animationTimer: Timer?
    private var screensAsleep = false
    private var menuOpen = false
    private var calmBurstUntil: TimeInterval = 0

    private lazy var timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        return f
    }()

    var notifierSupported: Bool { notifier.isSupported }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setUpStatusItem()
        observeSystem()
        if isDemo {
            publish(demoSnapshot())
        } else {
            startProbing()
        }
        updateAnimation()
    }

    func applicationWillTerminate(_ notification: Notification) {
        probeTimer?.cancel()
        animationTimer?.invalidate()
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Remembers a Cmd-drag position across launches.
        statusItem.autosaveName = "HeadroomStatusItem"

        menuBuilder = MenuBuilder(app: self)
        statusItem.menu = menuBuilder.menu

        statusView = StatusView(frame: statusItem.button?.bounds ?? .zero)
        statusView.autoresizingMask = [.width, .height]
        statusView.displayMode = settings.displayMode
        statusView.onPreferredWidthChange = { [weak self] width in
            self?.applyWidth(width)
        }

        if let button = statusItem.button {
            button.title = ""
            button.image = nil
            button.setAccessibilityLabel("Headroom, scanning")
            button.addSubview(statusView)
        }
        applyWidth(statusView.preferredWidth)
    }

    private func applyWidth(_ width: CGFloat) {
        statusItem.length = width
        if let button = statusItem.button {
            statusView.frame = button.bounds
        }
    }

    private func observeSystem() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(self, selector: #selector(screensDidSleep(_:)),
                                    name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspaceCenter.addObserver(self, selector: #selector(screensDidWake(_:)),
                                    name: NSWorkspace.screensDidWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(powerStateChanged(_:)),
                                               name: .NSProcessInfoPowerStateDidChange, object: nil)
    }

    @objc private func screensDidSleep(_ note: Notification) {
        screensAsleep = true
        updateAnimation()
    }

    @objc private func screensDidWake(_ note: Notification) {
        screensAsleep = false
        updateAnimation()
        refreshNow()
    }

    @objc private func powerStateChanged(_ note: Notification) {
        // Posted on an arbitrary thread.
        DispatchQueue.main.async { [weak self] in self?.updateAnimation() }
    }

    // MARK: - Data

    private func startProbing() {
        let provider = LiveProvider(settings: settings.headroomSettings)
        self.provider = provider
        let timer = DispatchSource.makeTimerSource(queue: probeQueue)
        timer.schedule(deadline: .now(), repeating: Self.probeInterval, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            let snapshot = provider.snapshot()
            DispatchQueue.main.async { self?.publish(snapshot) }
        }
        probeTimer = timer
        timer.resume()
    }

    func refreshNow() {
        if isDemo {
            publish(demoSnapshot())
            return
        }
        guard let provider else { return }
        let newSettings = settings.headroomSettings
        probeQueue.async { [weak self] in
            provider.settings = newSettings
            let snapshot = provider.snapshot()
            DispatchQueue.main.async { self?.publish(snapshot) }
        }
    }

    /// Fixtures.demo with headroom and level recomputed for the current reserve, so the menu reacts.
    private func demoSnapshot() -> Snapshot {
        var s = Fixtures.demo
        let math = settings.headroomSettings
        s.headroomAgents = Estimator.headroom(memory: s.memory, perAgentBytes: s.perAgentBytes, settings: math)
        s.level = Estimator.level(headroom: s.headroomAgents, memory: s.memory, settings: math)
        s.takenAt = Date().timeIntervalSince1970
        return s
    }

    private func publish(_ s: Snapshot) {
        let previousLevel = snapshot?.level
        snapshot = s

        if previousLevel != nil, previousLevel != s.level, settings.displayMode == .calm {
            calmBurstUntil = ProcessInfo.processInfo.systemUptime + Self.calmBurstDuration
        }

        statusView.update(with: s)
        if let button = statusItem.button {
            button.setAccessibilityLabel(Self.spokenSummary(s))
            let time = timeFormatter.string(from: Date(timeIntervalSince1970: s.takenAt))
            button.toolTip = "\(Format.line(s))\nUpdated \(time)"
        }
        if menuOpen {
            menuBuilder.header.snapshot = s
        }
        notifier.observe(s, enabled: settings.notifyOnDanger)
        updateAnimation()
    }

    static func spokenSummary(_ s: Snapshot) -> String {
        func count(_ n: Int, _ noun: String) -> String { n == 1 ? "1 \(noun)" : "\(n) \(noun)s" }
        let available = s.memory.availableBytes
        let memory = available >= 1 << 30
            ? String(format: "%.1f gigabytes free", Double(available) / Double(1 << 30))
            : "\(available >> 20) megabytes free"
        let fit: String
        switch s.headroomAgents {
        case 0: fit = "no more agents fit"
        case 1: fit = "1 more agent fits"
        default: fit = "\(s.headroomAgents) more agents fit"
        }
        var sentence = "\(count(s.agents.count, "agent")), \(count(s.terminals.sessions, "terminal")), \(memory), \(fit)"
        if s.level == .danger { sentence += ". Memory is critical, do not start another agent" }
        return sentence
    }

    // MARK: - Settings (called from the menu)

    func setReserve(gb: Int) {
        settings.reserveGB = gb
        menuBuilder.header.reserveBytes = settings.headroomSettings.reserveBytes
        refreshNow()
    }

    func setDisplayMode(_ mode: DisplayMode) {
        settings.displayMode = mode
        statusView.displayMode = mode
        calmBurstUntil = 0
        updateAnimation()
    }

    func setRainEnabled(_ enabled: Bool) {
        settings.rainEnabled = enabled
        updateAnimation()
    }

    func setMenuOpen(_ open: Bool) {
        menuOpen = open
        if open { menuBuilder.header.snapshot = snapshot }
        updateAnimation()
    }

    func showError(_ message: String, detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: - Animation

    /// Starts the 10 fps timer only while something actually moves; stops it otherwise.
    private func updateAnimation() {
        let now = ProcessInfo.processInfo.systemUptime
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let canAnimate = !lowPower && !screensAsleep

        let calmBurst = now < calmBurstUntil
        let rainShown = settings.rainEnabled && (settings.displayMode != .calm || calmBurst)
        statusView.rainVisible = rainShown
        statusView.rainRunning = rainShown && canAnimate
        statusView.pulseEnabled = canAnimate

        let headerAnimating = menuOpen && settings.rainEnabled && canAnimate
        menuBuilder.header.animating = headerAnimating

        let needsTimer = statusView.rainRunning || statusView.isPulsing || headerAnimating
        if needsTimer, animationTimer == nil {
            let timer = Timer(timeInterval: Self.frameInterval, target: self, selector: #selector(tick(_:)),
                              userInfo: nil, repeats: true)
            timer.tolerance = 0.02
            // .common keeps it running while the menu is tracking.
            RunLoop.main.add(timer, forMode: .common)
            animationTimer = timer
        } else if !needsTimer, let timer = animationTimer {
            timer.invalidate()
            animationTimer = nil
            statusView.needsDisplay = true
        }
    }

    @objc private func tick(_ timer: Timer) {
        if calmBurstUntil > 0, ProcessInfo.processInfo.systemUptime >= calmBurstUntil {
            calmBurstUntil = 0
            updateAnimation()
        }
        statusView.tick()
        menuBuilder.header.tick()
    }
}
