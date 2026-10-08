import AppKit
import HeadroomCore

/// The first menu item: the answer to "can I start one more agent?" in the Matrix style.
final class HeaderView: NSView {
    static let width: CGFloat = 320
    static let height: CGFloat = 160

    var snapshot: Snapshot? { didSet { needsDisplay = true } }
    var reserveBytes: UInt64 = 3 << 30 { didSet { needsDisplay = true } }
    /// Rain advances while the menu is open (set by the owner).
    var animating = false

    private let rain = MatrixRain(columnWidth: 9, rowHeight: 10, seed: 0x5EED_1234)

    private static let titleFont = NSFont.monospacedSystemFont(ofSize: 17, weight: .bold)
    private static let labelFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
    private static let smallFont = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizingMask = [.width]
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var isOpaque: Bool { false }

    func tick() {
        guard animating else { return }
        rain.step()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let card = bounds.insetBy(dx: 8, dy: 5)
        let cardPath = Palette.roundedPath(card, radius: 8)
        ctx.addPath(cardPath)
        ctx.setFillColor(Palette.pill.cgColor)
        ctx.fillPath()

        rain.layout(size: card.size)
        ctx.saveGState()
        ctx.addPath(cardPath)
        ctx.clip()
        rain.draw(in: ctx, rect: card, intensity: 0.55)
        ctx.restoreGState()

        ctx.addPath(Palette.roundedPath(card.insetBy(dx: 0.5, dy: 0.5), radius: 7.5))
        ctx.setStrokeColor(Palette.neon.withAlphaComponent(0.3).cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()

        let left = card.minX + 14
        let barWidth = card.width - 28
        var top = card.maxY - 12

        guard let s = snapshot else {
            _ = drawText("SCANNING...", font: Self.titleFont, color: Palette.neon, x: left, top: top, glow: true)
            return
        }

        // Title.
        let levelColor = Palette.color(for: s.level)
        top -= drawText(Self.title(for: s), font: Self.titleFont, color: levelColor, x: left, top: top, glow: true) + 10

        // Memory bar: in use | usable available | reserve.
        let m = s.memory
        let total = max(m.totalBytes, 1)
        let inUse = m.totalBytes > m.availableBytes ? m.totalBytes - m.availableBytes : 0
        let reserve = min(reserveBytes, m.availableBytes)
        let usable = m.availableBytes - reserve
        let memLabel = "MEM  \(Format.bytes(inUse)) used  \(Format.bytes(m.availableBytes)) free  \(Format.bytes(reserveBytes)) rsv"
        top -= drawText(memLabel, font: Self.labelFont, color: Palette.neon.withAlphaComponent(0.85), x: left, top: top, glow: false) + 3
        drawBar(ctx, CGRect(x: left, y: top - 7, width: barWidth, height: 7), segments: [
            (CGFloat(Double(inUse) / Double(total)), Palette.neon.withAlphaComponent(0.35)),
            (CGFloat(Double(usable) / Double(total)), Palette.neon),
            (CGFloat(Double(reserve) / Double(total)), Palette.amber.withAlphaComponent(0.75)),
        ])
        top -= 7 + 9

        // Swap bar.
        let swapRatio = m.swapTotalBytes > 0 ? Double(m.swapUsedBytes) / Double(m.swapTotalBytes) : 0
        let swapColor: NSColor = swapRatio >= 0.85 ? Palette.red : (swapRatio >= 0.5 ? Palette.amber : Palette.neon)
        let swapLabel = m.swapTotalBytes > 0
            ? "SWAP \(Format.bytes(m.swapUsedBytes)) / \(Format.bytes(m.swapTotalBytes))  \(Int((swapRatio * 100).rounded()))%"
            : "SWAP none in use"
        top -= drawText(swapLabel, font: Self.labelFont, color: Palette.neon.withAlphaComponent(0.85), x: left, top: top, glow: false) + 3
        drawBar(ctx, CGRect(x: left, y: top - 7, width: barWidth, height: 7), segments: [
            (CGFloat(min(swapRatio, 1)), swapColor),
        ])
        top -= 7 + 10

        // Pressure and per-agent estimate.
        let pressure = "PRESSURE \(m.pressure.rawValue.uppercased())   \(m.freePercent)% FREE"
        top -= drawText(pressure, font: Self.smallFont, color: Palette.color(for: m.pressure), x: left, top: top, glow: false) + 4
        _ = drawText(Self.estimateLine(for: s), font: Self.smallFont, color: Palette.neon.withAlphaComponent(0.85),
                     x: left, top: top, glow: false)
    }

    static func title(for s: Snapshot) -> String {
        let n = s.headroomAgents
        if s.level == .danger {
            if n == 0 { return "STOP. 0 MORE AGENTS FIT" }
            let m = s.memory
            if m.swapTotalBytes > 0, Double(m.swapUsedBytes) / Double(m.swapTotalBytes) >= 0.85 {
                return "STOP. SWAP NEARLY FULL"
            }
            return "STOP. MEMORY CRITICAL"
        }
        return n == 1 ? "+1 MORE AGENT FITS" : "+\(n) MORE AGENTS FIT"
    }

    static func estimateLine(for s: Snapshot) -> String {
        let per = Format.bytes(s.perAgentBytes)
        let count = s.agents.count
        if count == 0 { return "1 agent ~ \(per) (default, none running)" }
        return "1 agent ~ \(per) (median of \(count) running)"
    }

    /// Draws one line with its top edge at `top`; returns the line height.
    private func drawText(_ text: String, font: NSFont, color: NSColor, x: CGFloat, top: CGFloat, glow: Bool) -> CGFloat {
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if glow {
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 4
            shadow.shadowOffset = .zero
            shadow.shadowColor = color.withAlphaComponent(0.8)
            attributes[.shadow] = shadow
        }
        let string = text as NSString
        let height = ceil(font.ascender - font.descender + font.leading)
        string.draw(at: NSPoint(x: x, y: top - height), withAttributes: attributes)
        return height
    }

    private func drawBar(_ ctx: CGContext, _ rect: CGRect, segments: [(CGFloat, NSColor)]) {
        let track = Palette.roundedPath(rect, radius: 2)
        ctx.saveGState()
        ctx.addPath(track)
        ctx.clip()
        ctx.setFillColor(Palette.neon.withAlphaComponent(0.1).cgColor)
        ctx.fill(rect)
        var x = rect.minX
        for (fraction, color) in segments {
            let w = rect.width * max(0, min(1, fraction))
            guard w > 0 else { continue }
            ctx.setFillColor(color.cgColor)
            ctx.fill(CGRect(x: x, y: rect.minY, width: w, height: rect.height))
            x += w
        }
        ctx.restoreGState()
        ctx.addPath(Palette.roundedPath(rect.insetBy(dx: 0.5, dy: 0.5), radius: 1.5))
        ctx.setStrokeColor(Palette.neon.withAlphaComponent(0.3).cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()
    }
}

/// Builds the status item menu each time it opens (menuNeedsUpdate).
final class MenuBuilder: NSObject, NSMenuDelegate {
    static let repositoryURL = URL(string: "https://github.com/theluckystrike/headroom")!

    let menu = NSMenu()
    let header = HeaderView(frame: NSRect(x: 0, y: 0, width: HeaderView.width, height: HeaderView.height))
    private weak var app: AppDelegate?

    private static let itemFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let sectionFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)

    init(app: AppDelegate) {
        self.app = app
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild()
    }

    func menuWillOpen(_ menu: NSMenu) {
        app?.setMenuOpen(true)
    }

    func menuDidClose(_ menu: NSMenu) {
        app?.setMenuOpen(false)
    }

    // MARK: - Building

    private func rebuild() {
        menu.removeAllItems()
        guard let app else { return }
        let settings = app.settings

        header.snapshot = app.snapshot
        header.reserveBytes = settings.headroomSettings.reserveBytes
        let headerItem = NSMenuItem()
        headerItem.view = header
        menu.addItem(headerItem)

        if app.isDemo { menu.addItem(info("DEMO DATA (--demo)", color: .secondaryLabelColor)) }

        if let s = app.snapshot {
            addAgentSections(s)
            addTerminalSection(s)
        } else {
            menu.addItem(.separator())
            menu.addItem(info("Scanning processes...", color: .secondaryLabelColor))
        }

        menu.addItem(.separator())

        // Reserve submenu.
        let reserveItem = NSMenuItem(title: "Reserve: \(settings.reserveGB) GB", action: nil, keyEquivalent: "")
        let reserveMenu = NSMenu()
        reserveMenu.autoenablesItems = false
        for gb in AppSettings.reserveChoicesGB {
            let item = action("\(gb) GB", #selector(pickReserve(_:)))
            item.representedObject = gb
            item.state = gb == settings.reserveGB ? .on : .off
            reserveMenu.addItem(item)
        }
        reserveItem.submenu = reserveMenu
        menu.addItem(reserveItem)

        // Display submenu.
        let displayItem = NSMenuItem(title: "Display: \(settings.displayMode.title)", action: nil, keyEquivalent: "")
        let displayMenu = NSMenu()
        displayMenu.autoenablesItems = false
        for mode in DisplayMode.allCases {
            let item = action(mode.title, #selector(pickDisplayMode(_:)))
            item.representedObject = mode.rawValue
            item.state = mode == settings.displayMode ? .on : .off
            displayMenu.addItem(item)
        }
        displayItem.submenu = displayMenu
        menu.addItem(displayItem)

        let rainItem = action("Rain animation", #selector(toggleRain(_:)))
        rainItem.state = settings.rainEnabled ? .on : .off
        menu.addItem(rainItem)

        menu.addItem(loginItem())

        let notifyItem = action("Notify when headroom hits 0", #selector(toggleNotify(_:)))
        notifyItem.state = settings.notifyOnDanger ? .on : .off
        if !app.notifierSupported {
            notifyItem.title = "Notify when headroom hits 0 (needs Headroom.app)"
            notifyItem.isEnabled = false
        }
        menu.addItem(notifyItem)

        menu.addItem(.separator())
        let refresh = action("Refresh now", #selector(refreshNow(_:)))
        refresh.keyEquivalent = "r"
        menu.addItem(refresh)
        let copy = action("Copy snapshot JSON", #selector(copyJSON(_:)))
        copy.keyEquivalent = "c"
        copy.isEnabled = app.snapshot != nil
        menu.addItem(copy)
        menu.addItem(action("Open Activity Monitor", #selector(openActivityMonitor(_:))))
        menu.addItem(action("Headroom on GitHub", #selector(openGitHub(_:))))

        menu.addItem(.separator())
        let quit = action("Quit Headroom", #selector(quit(_:)))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func addAgentSections(_ s: Snapshot) {
        menu.addItem(.separator())
        menu.addItem(section("AGENTS  \(s.agents.count)"))
        if s.agents.isEmpty {
            menu.addItem(info("no agents running", color: .secondaryLabelColor))
        } else {
            var groups: [AgentKind: (count: Int, total: UInt64)] = [:]
            for agent in s.agents {
                groups[agent.kind, default: (0, 0)].count += 1
                groups[agent.kind, default: (0, 0)].total += agent.treeBytes
            }
            let sorted = groups.sorted { $0.value.total > $1.value.total }
            for (kind, group) in sorted {
                let avg = group.total / UInt64(max(group.count, 1))
                let line = pad(kind.label, 13) + pad("x\(group.count)", 5)
                    + pad("avg \(Format.bytes(avg))", 10) + "\(Format.bytes(group.total)) total"
                menu.addItem(info(line))
            }
        }

        if !s.agents.isEmpty {
            menu.addItem(.separator())
            menu.addItem(section("HEAVIEST SESSIONS"))
            for agent in s.agents.sorted(by: { $0.treeBytes > $1.treeBytes }).prefix(5) {
                let procs = agent.processCount == 1 ? "1 proc" : "\(agent.processCount) procs"
                let line = pad(agent.kind.rawValue, 9) + pad(agent.tty ?? "-", 9)
                    + pad(Format.bytes(agent.treeBytes), 7) + procs
                menu.addItem(info(line))
            }
        }
    }

    private func addTerminalSection(_ s: Snapshot) {
        menu.addItem(.separator())
        menu.addItem(section("TERMINALS  \(s.terminals.sessions)"))
        let apps = s.terminals.byApp.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        for (name, count) in apps {
            menu.addItem(info(pad(name, 18) + "\(count)"))
        }
        let total = s.terminals.sessions == 1 ? "1 session" : "\(s.terminals.sessions) sessions"
        menu.addItem(info(pad("Total", 18) + total))
    }

    private func loginItem() -> NSMenuItem {
        let item = action("Launch at login", #selector(toggleLaunchAtLogin(_:)))
        if !LoginItem.isSupported {
            item.title = "Launch at login (needs Headroom.app)"
            item.isEnabled = false
        } else if LoginItem.requiresApproval {
            item.title = "Launch at login (approve in System Settings)"
            item.state = .mixed
        } else {
            item.state = LoginItem.isEnabled ? .on : .off
        }
        return item
    }

    // MARK: - Item helpers

    private func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text.padding(toLength: width, withPad: " ", startingAt: 0)
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    /// A read-only monospaced row. Disabled so it cannot be clicked; the explicit color keeps it readable.
    private func info(_ text: String, color: NSColor = .labelColor) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: text, attributes: [.font: Self.itemFont, .foregroundColor: color])
        item.isEnabled = false
        return item
    }

    private func section(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: Self.sectionFont, .foregroundColor: NSColor.secondaryLabelColor, .kern: 0.5,
        ])
        item.isEnabled = false
        return item
    }

    // MARK: - Actions

    @objc private func pickReserve(_ sender: NSMenuItem) {
        guard let gb = sender.representedObject as? Int else { return }
        app?.setReserve(gb: gb)
    }

    @objc private func pickDisplayMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = DisplayMode(rawValue: raw) else { return }
        app?.setDisplayMode(mode)
    }

    @objc private func toggleRain(_ sender: NSMenuItem) {
        guard let app else { return }
        app.setRainEnabled(!app.settings.rainEnabled)
    }

    @objc private func toggleNotify(_ sender: NSMenuItem) {
        guard let app else { return }
        app.settings.notifyOnDanger.toggle()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        if LoginItem.requiresApproval {
            LoginItem.openSystemSettings()
            return
        }
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            app?.showError("Could not change Launch at login", detail: error.localizedDescription)
        }
    }

    @objc private func refreshNow(_ sender: NSMenuItem) {
        app?.refreshNow()
    }

    @objc private func copyJSON(_ sender: NSMenuItem) {
        guard let s = app?.snapshot else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Format.json(s), forType: .string)
    }

    @objc private func openActivityMonitor(_ sender: NSMenuItem) {
        let workspace = NSWorkspace.shared
        if let url = workspace.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
            workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        } else {
            workspace.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
        }
    }

    @objc private func openGitHub(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(Self.repositoryURL)
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}
