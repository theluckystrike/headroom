import AppKit
import CoreText
import HeadroomCore

/// The Matrix palette, sRGB.
enum Palette {
    static let neon = NSColor(srgbRed: 0, green: 1, blue: CGFloat(0x41) / 255, alpha: 1)        // #00FF41
    static let pill = NSColor(srgbRed: CGFloat(0x03) / 255, green: CGFloat(0x08) / 255,
                              blue: CGFloat(0x03) / 255, alpha: 1)                                // #030803
    static let amber = NSColor(srgbRed: 1, green: CGFloat(0xB0) / 255, blue: 0, alpha: 1)       // #FFB000
    static let red = NSColor(srgbRed: 1, green: CGFloat(0x3B) / 255, blue: CGFloat(0x30) / 255, alpha: 1) // #FF3B30

    static func color(for level: HeadroomLevel) -> NSColor {
        switch level {
        case .ok: return neon
        case .tight: return amber
        case .danger: return red
        }
    }

    static func color(for pressure: PressureLevel) -> NSColor {
        switch pressure {
        case .normal: return neon
        case .warning: return amber
        case .critical: return red
        }
    }

    /// CGPath(roundedRect:) traps when the radius exceeds half the rect; clamp it.
    static func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let r = max(0, min(radius, rect.width / 2, rect.height / 2))
        return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    }
}

/// The menu bar item: a near-black pill with Matrix rain behind neon segments.
/// Added as a subview of the status item's button; clicks pass through to the button.
final class StatusView: NSView {
    private static let font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .bold)
    private static let horizontalPadding: CGFloat = 7
    private static let segmentGap: CGFloat = 9
    private static let outerInset: CGFloat = 1
    private static let verticalInset: CGFloat = 2
    private static let cornerRadius: CGFloat = 5

    var displayMode: DisplayMode = .full {
        didSet { if oldValue != displayMode { rebuildLines() } }
    }
    /// Rain is drawn at all (frozen when not running).
    var rainVisible = true {
        didSet { if oldValue != rainVisible { needsDisplay = true } }
    }
    /// Rain advances on each tick.
    var rainRunning = false
    /// The danger segment pulses on each tick.
    var pulseEnabled = false {
        didSet { if oldValue != pulseEnabled { needsDisplay = true } }
    }
    /// Called when the text width changes so the owner can resize the status item.
    var onPreferredWidthChange: ((CGFloat) -> Void)?
    private(set) var preferredWidth: CGFloat = 60

    private(set) var level: HeadroomLevel = .ok
    private var mainText = ""
    private var plusText = ""
    private var mainLine: CTLine?
    private var mainWidth: CGFloat = 0
    private var plusLine: CTLine?
    private var plusWidth: CGFloat = 0
    private let rain = MatrixRain(columnWidth: 7, rowHeight: 8.5, seed: 0x4845_4144)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setPlaceholder()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setPlaceholder()
    }

    // Let the status item button receive every click (it owns the menu).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isOpaque: Bool { false }
    override func isAccessibilityElement() -> Bool { false }

    var isPulsing: Bool { pulseEnabled && level == .danger }

    // MARK: - Data

    func update(with s: Snapshot) {
        let main = "AG \(s.agents.count)  TTY \(s.terminals.sessions)  \(Format.bytes(s.memory.availableBytes))"
        let plus = "+\(s.headroomAgents)"
        let levelChanged = s.level != level
        level = s.level
        if main != mainText || plus != plusText {
            mainText = main
            plusText = plus
            rebuildLines()
        } else if levelChanged {
            needsDisplay = true
        }
    }

    private func setPlaceholder() {
        mainText = "AG --  TTY --  --.-G"
        plusText = "+-"
        rebuildLines()
    }

    private func rebuildLines() {
        let dim = Palette.neon.withAlphaComponent(0.6).cgColor
        let bright = Palette.neon.cgColor
        let colorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)

        // Labels (AG, TTY) dimmer than the numbers.
        let main = NSMutableAttributedString()
        for (index, word) in mainText.split(separator: " ", omittingEmptySubsequences: false).enumerated() {
            if index > 0 { main.append(NSAttributedString(string: " ", attributes: [.font: Self.font, colorKey: dim])) }
            let isLabel = word.first?.isLetter == true && word.last?.isLetter == true
            main.append(NSAttributedString(string: String(word),
                                           attributes: [.font: Self.font, colorKey: isLabel ? dim : bright]))
        }
        mainLine = CTLineCreateWithAttributedString(main as CFAttributedString)
        mainWidth = CGFloat(CTLineGetTypographicBounds(mainLine!, nil, nil, nil))

        // The +N segment takes its color from the context so it can change level or pulse without a rebuild.
        let plus = NSAttributedString(string: plusText, attributes: [
            .font: Self.font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ])
        plusLine = CTLineCreateWithAttributedString(plus as CFAttributedString)
        plusWidth = CGFloat(CTLineGetTypographicBounds(plusLine!, nil, nil, nil))

        var width = Self.horizontalPadding * 2 + plusWidth + Self.outerInset * 2
        if displayMode != .compact { width += mainWidth + Self.segmentGap }
        width = width.rounded(.up)
        needsDisplay = true
        if width != preferredWidth {
            preferredWidth = width
            onPreferredWidthChange?(width)
        }
    }

    // MARK: - Animation

    /// Called at 10 fps by the owner while any animation is active.
    func tick() {
        if rainRunning && rainVisible { rain.step() }
        if (rainRunning && rainVisible) || isPulsing { needsDisplay = true }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let pillRect = bounds.insetBy(dx: Self.outerInset, dy: Self.verticalInset)
        guard pillRect.width > 4, pillRect.height > 4 else { return }
        let pillPath = Palette.roundedPath(pillRect, radius: Self.cornerRadius)

        // Pill.
        ctx.addPath(pillPath)
        ctx.setFillColor(Palette.pill.cgColor)
        ctx.fillPath()

        // Rain, clipped to the pill.
        if rainVisible {
            rain.layout(size: pillRect.size)
            ctx.saveGState()
            ctx.addPath(pillPath)
            ctx.clip()
            rain.draw(in: ctx, rect: pillRect, intensity: 1)
            ctx.restoreGState()
        }

        // 1px border, #00FF41 at 30%.
        let scale = window?.backingScaleFactor ?? 2
        let hairline = 1 / scale
        ctx.addPath(Palette.roundedPath(pillRect.insetBy(dx: hairline / 2, dy: hairline / 2),
                                        radius: Self.cornerRadius - hairline / 2))
        ctx.setStrokeColor(Palette.neon.withAlphaComponent(0.3).cgColor)
        ctx.setLineWidth(hairline)
        ctx.strokePath()

        // Text: vertically centered on cap height, snapped to the pixel grid.
        let rawBaseline = pillRect.midY - Self.font.capHeight / 2
        let baseline = (rawBaseline * scale).rounded() / scale
        ctx.textMatrix = .identity
        var x = pillRect.minX + Self.horizontalPadding

        if displayMode != .compact, let mainLine {
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 3, color: Palette.neon.withAlphaComponent(0.8).cgColor)
            ctx.textPosition = CGPoint(x: x, y: baseline)
            CTLineDraw(mainLine, ctx)
            ctx.restoreGState()
            x += mainWidth + Self.segmentGap
        }

        if let plusLine {
            var alpha: CGFloat = 1
            if isPulsing {
                // Slow 1.2 s pulse between 45% and 100%.
                let phase = ProcessInfo.processInfo.systemUptime.truncatingRemainder(dividingBy: 1.2) / 1.2
                alpha = 0.45 + 0.55 * CGFloat(0.5 + 0.5 * cos(2 * Double.pi * phase))
            }
            let color = Palette.color(for: level)
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 3, color: color.withAlphaComponent(0.8 * alpha).cgColor)
            ctx.setFillColor(color.withAlphaComponent(alpha).cgColor)
            ctx.textPosition = CGPoint(x: x, y: baseline)
            CTLineDraw(plusLine, ctx)
            ctx.restoreGState()
        }
    }
}
