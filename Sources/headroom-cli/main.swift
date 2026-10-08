// headroom: how many more AI coding agents fit in memory, from the terminal.
//
//   headroom            human summary
//   headroom --line     one line for tmux status-right / Claude Code statusLine
//   headroom --json     full snapshot as JSON
//   headroom --watch    redraw every 2 s

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import HeadroomCore
#if os(macOS)
import HeadroomMac
#endif

let version = "0.1.0"

let usage = """
usage: headroom [--line | --json] [--watch] [--reserve SIZE] [--per-agent SIZE]

How many more AI coding agents fit in memory before the Mac swaps hard.

  (no flag)          short human summary
  --line             one line, for tmux status-right or a Claude Code statusLine
  --json             full snapshot as JSON
  --watch, -w        redraw every 2 seconds (Ctrl-C to stop)
  --reserve SIZE     memory kept free for the OS and bursts (default 3G)
  --per-agent SIZE   cost of one more agent; overrides the measured mean (default: measured,
                     600M when no agents run)
  --help, -h         this help
  --version, -v      print the version

SIZE is bytes or a number with K, M, G or T (binary units), e.g. 3G, 600M, 1.5G.
Color follows NO_COLOR and is only used when stdout is a terminal.
"""

enum Mode { case human, line, json }

struct Options {
    var mode: Mode = .human
    var watch = false
    var reserve: UInt64? = nil
    var perAgent: UInt64? = nil
}

func fail(_ message: String) -> Never {
    fputs("headroom: \(message)\n\(usage)\n", stderr)
    exit(2)
}

/// "3G" -> 3 GiB, "600M" -> 600 MiB, "1.5G", "512k", "3GB", "3GiB", "1048576".
func parseSize(_ text: String) -> UInt64? {
    var s = Substring(text.trimmingSpaces().uppercased())
    if s.hasSuffix("IB") { s = s.dropLast(2) } else if s.hasSuffix("B") && s.count > 1 { s = s.dropLast(1) }
    var multiplier: Double = 1
    if let last = s.last, let shift = ["K": 10, "M": 20, "G": 30, "T": 40][String(last)] {
        multiplier = Double(UInt64(1) << UInt64(shift))
        s = s.dropLast()
    }
    guard let value = Double(s), value.isFinite, value >= 0 else { return nil }
    let bytes = value * multiplier
    guard bytes < Double(UInt64.max / 2) else { return nil }
    return UInt64(bytes)
}

extension String {
    func trimmingSpaces() -> String {
        var s = Substring(self)
        while s.first == " " || s.first == "\t" { s = s.dropFirst() }
        while s.last == " " || s.last == "\t" { s = s.dropLast() }
        return String(s)
    }
}

func parseOptions(_ argv: [String]) -> Options {
    var o = Options()
    var i = 0
    func value(_ flag: String) -> String {
        i += 1
        guard i < argv.count else { fail("\(flag) needs a value") }
        return argv[i]
    }
    while i < argv.count {
        var arg = argv[i]
        var inline: String? = nil
        if arg.hasPrefix("--"), let eq = arg.firstIndex(of: "=") {
            inline = String(arg[arg.index(after: eq)...])
            arg = String(arg[..<eq])
        }
        switch arg {
        case "--line", "-l": o.mode = .line
        case "--json", "-j": o.mode = .json
        case "--watch", "-w": o.watch = true
        case "--help", "-h":
            print(usage)
            exit(0)
        case "--version", "-v", "-V":
            print("headroom \(version)")
            exit(0)
        case "--reserve", "--per-agent":
            let text = inline ?? value(arg)
            guard let bytes = parseSize(text) else { fail("bad size for \(arg): \(text)") }
            if arg == "--reserve" { o.reserve = bytes } else {
                guard bytes > 0 else { fail("--per-agent must be more than 0") }
                o.perAgent = bytes
            }
        default:
            fail("unknown option \(argv[i])")
        }
        i += 1
    }
    return o
}

/// Applies --per-agent: unlike settings.defaultPerAgentBytes (used only when no agents run),
/// the flag replaces the measured mean, so headroom and level are recomputed.
func applyPerAgent(_ snapshot: Snapshot, perAgent: UInt64?, settings: HeadroomSettings) -> Snapshot {
    guard let perAgent else { return snapshot }
    var s = snapshot
    s.perAgentBytes = perAgent
    s.headroomAgents = Estimator.headroom(memory: s.memory, perAgentBytes: perAgent, settings: settings)
    s.level = Estimator.level(headroom: s.headroomAgents, memory: s.memory, settings: settings)
    return s
}

// MARK: - human output

struct Style {
    var on: Bool
    var trueColor: Bool
    var green: String { on ? (trueColor ? "\u{1B}[38;2;0;255;65m" : "\u{1B}[92m") : "" }
    var dim: String { on ? (trueColor ? "\u{1B}[38;2;0;143;17m" : "\u{1B}[32m") : "" }
    var amber: String { on ? "\u{1B}[93m" : "" }
    var red: String { on ? "\u{1B}[91m" : "" }
    var bold: String { on ? "\u{1B}[1m" : "" }
    var reset: String { on ? "\u{1B}[0m" : "" }

    static func detect() -> Style {
        let tty = isatty(STDOUT_FILENO) == 1
        let noColor = getenv("NO_COLOR").map { String(cString: $0) }.map { !$0.isEmpty } ?? false
        let colorterm = getenv("COLORTERM").map { String(cString: $0).lowercased() } ?? ""
        return Style(on: tty && !noColor, trueColor: colorterm == "truecolor" || colorterm == "24bit")
    }
}

func pad(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
}

func padLeft(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : String(repeating: " ", count: width - s.count) + s
}

func render(_ s: Snapshot, settings: HeadroomSettings, perAgentOverridden: Bool, style st: Style) -> String {
    var out: [String] = []
    let n = s.headroomAgents
    let levelColor: String
    switch s.level {
    case .ok: levelColor = st.green
    case .tight: levelColor = st.amber
    case .danger: levelColor = st.red
    }
    let noun = n == 1 ? "agent fits" : "agents fit"
    var headline = "+\(n) more \(noun)"
    if s.level == .danger { headline += n == 0 ? ": do not start another" : ": but memory is already in danger" }
    out.append("\(st.bold)\(levelColor)\(headline)\(st.reset)")
    out.append("")

    // Agents by kind.
    let mem = s.memory
    out.append("\(st.green)\(st.bold)AGENTS\(st.reset)\(st.green) \(s.agents.count) running\(st.reset)")
    var groups: [AgentKind: (count: Int, bytes: UInt64)] = [:]
    for a in s.agents {
        let g = groups[a.kind] ?? (0, 0)
        groups[a.kind] = (g.count + 1, g.bytes + a.treeBytes)
    }
    let kinds = groups.sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key.label < $1.key.label }
    if kinds.isEmpty {
        out.append("\(st.dim)  none\(st.reset)")
    }
    for (kind, g) in kinds {
        let avg = g.bytes / UInt64(max(g.count, 1))
        out.append("\(st.green)  \(pad(kind.label, 14))\(padLeft(String(g.count), 4))   avg \(padLeft(Format.bytes(avg), 6))   total \(padLeft(Format.bytes(g.bytes), 6))\(st.reset)")
    }
    out.append("")

    // Terminals by app.
    out.append("\(st.green)\(st.bold)TERMINALS\(st.reset)\(st.green) \(s.terminals.sessions) sessions\(st.reset)")
    let apps = s.terminals.byApp.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
    if apps.isEmpty {
        out.append("\(st.dim)  none\(st.reset)")
    }
    for (app, count) in apps {
        out.append("\(st.green)  \(pad(app, 14))\(padLeft(String(count), 4))\(st.reset)")
    }
    out.append("")

    // Memory.
    let pressureColor = mem.pressure == .normal ? st.green : (mem.pressure == .warning ? st.amber : st.red)
    out.append("\(st.green)\(st.bold)MEMORY\(st.reset)")
    out.append("\(st.green)  available   \(Format.bytes(mem.availableBytes)) of \(Format.bytes(mem.totalBytes)) (app + wired + compressed = \(Format.bytes(mem.totalBytes > mem.availableBytes ? mem.totalBytes - mem.availableBytes : 0)) used)\(st.reset)")
    out.append("\(st.green)  compressed  \(Format.bytes(mem.compressedBytes))\(st.reset)")
    let swapRatio = mem.swapTotalBytes > 0 ? Double(mem.swapUsedBytes) / Double(mem.swapTotalBytes) : 0
    let swapColor = swapRatio >= settings.swapDangerRatio ? st.red : st.green
    let swapText = mem.swapTotalBytes > 0
        ? "\(Format.bytes(mem.swapUsedBytes)) of \(Format.bytes(mem.swapTotalBytes)) (\(Int((swapRatio * 100).rounded()))%)"
        : "none"
    out.append("\(st.green)  swap        \(swapColor)\(swapText)\(st.reset)")
    out.append("\(st.green)  pressure    \(pressureColor)\(mem.pressure.rawValue)\(st.reset)")
    if mem.diskFreeBytes > 0 {
        let diskColor = mem.diskFreeBytes < settings.lowDiskBytes ? st.red : st.green
        out.append("\(st.green)  disk free   \(diskColor)\(Format.bytes(mem.diskFreeBytes))\(st.reset)\(st.dim) (room for swap to grow)\(st.reset)")
    }
    out.append("")

    // Method.
    let source: String
    if perAgentOverridden {
        source = "set by --per-agent"
    } else if s.agents.isEmpty {
        source = "default, no agents running to measure"
    } else {
        source = "mean of \(s.agents.count) running agent trees (incl. MCP servers), clamped to 150M..4G"
    }
    out.append("\(st.dim)method: (available \(Format.bytes(mem.availableBytes)) - reserve \(Format.bytes(Estimator.effectiveReserve(memory: mem, settings: settings)))\(mem.pressure == .warning ? " (2x, warning pressure)" : "")) / \(Format.bytes(s.perAgentBytes)) per agent = \(n)\(st.reset)")
    out.append("\(st.dim)        per agent: \(source)\(st.reset)")
    out.append("\(st.dim)        available = total - (app memory + wired + compressed), as Activity Monitor counts it\(st.reset)")
    if s.level == .danger && n > 0 {
        out.append("\(st.dim)        level is danger: swap is \(Int(settings.swapDangerRatio * 100))%+ full and the disk is too low for it to grow\(st.reset)")
    }
    return out.joined(separator: "\n")
}

func output(_ s: Snapshot, options: Options, settings: HeadroomSettings, style: Style) -> String {
    switch options.mode {
    case .line: return Format.line(s)
    case .json: return Format.json(s)
    case .human: return render(s, settings: settings, perAgentOverridden: options.perAgent != nil, style: style)
    }
}

// MARK: - main

let options = parseOptions(Array(CommandLine.arguments.dropFirst()))
var settings = HeadroomSettings()
if let reserve = options.reserve { settings.reserveBytes = reserve }
if let perAgent = options.perAgent { settings.defaultPerAgentBytes = perAgent }
let style = options.mode == .human ? Style.detect() : Style(on: false, trueColor: false)

#if os(macOS)
let provider = LiveProvider(settings: settings)
func take() -> Snapshot { applyPerAgent(provider.snapshot(), perAgent: options.perAgent, settings: settings) }

if options.watch {
    signal(SIGINT) { _ in
        // Restore the cursor and leave the last frame on screen.
        fputs("\u{1B}[?25h\n", stdout)
        exit(0)
    }
    let interactive = isatty(STDOUT_FILENO) == 1
    if interactive { fputs("\u{1B}[?25l", stdout) }
    while true {
        let text = output(take(), options: options, settings: settings, style: style)
        if interactive {
            fputs("\u{1B}[H\u{1B}[2J" + text + "\n", stdout)
        } else {
            fputs(text + "\n", stdout)
        }
        fflush(stdout)
        sleep(2)
    }
} else {
    print(output(take(), options: options, settings: settings, style: style))
}
#else
fputs("headroom: this build has no probes; headroom reads live data on macOS only\n", stderr)
exit(1)
#endif
