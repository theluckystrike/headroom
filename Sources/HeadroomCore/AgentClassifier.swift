// Decides whether one process is the root of an AI coding agent session.
//
// The rules are deliberately narrow. A false positive inflates the agent count and
// drags the per-agent estimate around; a missed agent only means its memory is not
// attributed, which the free-memory number still accounts for.

public enum AgentClassifier {
    /// Returns the agent kind when `p` is the ROOT process of an interactive or headless agent session.
    /// Helper processes (codex-code-mode-host, app-server daemons, MCP servers, chrome-native-host) return nil.
    public static func classify(_ p: ProcInfo) -> AgentKind? {
        let name = basename(p.name)
        if name.isEmpty { return nil }

        // Cheap gate first: almost every process on a Mac is rejected by one dictionary lookup
        // or one prefix check. Shells and multiplexers (zsh -c "claude ...", tmux new-session claude)
        // never pass it: they only wrap the agent, the real agent is their child.
        let native = nativeNames[name] // case-sensitive: "Claude" with a capital C is the desktop app
        let lower = native == nil ? name.lowercased() : name
        let isJS = native == nil && (lower == "node" || lower == "bun" || lower == "nodejs")
        let isPython = native == nil && !isJS && lower.hasPrefix("python")
        if native == nil && !isJS && !isPython { return nil }

        // Global exclusions: the Claude desktop app bundle and browser bridge hosts.
        if p.args.first.map { has($0, "/Claude.app/") } == true { return nil }
        if p.args.contains(where: { has($0, "chrome-native-host") }) { return nil }

        if let kind = native {
            return acceptNative(kind, rest: Array(p.args.dropFirst())) ? kind : nil
        }
        if isJS { return classifyScript(p.args, rules: jsRules) }
        return classifyPython(p.args)
    }

    // MARK: - Tables

    static let nativeNames: [String: AgentKind] = [
        "claude": .claude,
        "codex": .codex,
        "gemini": .gemini,
        "hermes": .hermes,
        "aider": .aider,
        "opencode": .opencode,
        "goose": .goose,
        "cursor-agent": .cursor,
        "amp": .amp,
        "copilot": .copilot,
        "droid": .droid,
        "crush": .crush,
        "qwen": .qwen,
    ]

    /// Subcommands that run a daemon, a server for another tool, or a short-lived admin
    /// command rather than an agent session. Checked against the first positional argument.
    static let nonSessionSubcommands: [AgentKind: Set<String>] = [
        .claude: ["mcp", "update", "doctor", "install", "setup-token", "migrate-installer"],
        .codex: ["app-server", "mcp-server", "mcp", "proto", "login", "logout", "completion", "debug", "sandbox", "apply"],
        .gemini: ["mcp", "extensions"],
        .hermes: ["gateway", "modellock"],
        .opencode: ["mcp", "auth", "upgrade", "models"],
        .goose: ["mcp", "configure", "info", "update", "version", "help", "web", "serve"],
        .amp: ["mcp", "login", "logout", "update"],
        .copilot: ["mcp", "login", "logout", "update"],
        .qwen: ["mcp", "extensions"],
    ]

    /// Arguments that anywhere in argv mark a helper rather than a session.
    static let poisonArgs: [AgentKind: [String]] = [
        .codex: ["pid-update-loop", "app-server", "codex-code-mode-host"],
        .hermes: ["modellock"],
    ]

    struct ScriptRule {
        let kind: AgentKind
        /// Substrings that identify the package in the script path.
        let pathMarkers: [String]
        /// Script basenames (extension stripped), e.g. the shebang launcher "/opt/homebrew/bin/claude".
        let basenames: Set<String>
    }

    static let jsRules: [ScriptRule] = [
        ScriptRule(kind: .claude, pathMarkers: ["@anthropic-ai/claude-code/", "claude-code/cli.js"], basenames: ["claude"]),
        ScriptRule(kind: .codex, pathMarkers: ["@openai/codex/"], basenames: ["codex"]),
        ScriptRule(kind: .gemini, pathMarkers: ["@google/gemini-cli/"], basenames: ["gemini"]),
        ScriptRule(kind: .amp, pathMarkers: ["@sourcegraph/amp/"], basenames: ["amp"]),
        // "@github/copilot-language-server" is the editor LSP, not the CLI: the trailing slash keeps it out.
        ScriptRule(kind: .copilot, pathMarkers: ["@github/copilot/"], basenames: ["copilot"]),
        ScriptRule(kind: .qwen, pathMarkers: ["@qwen-code/"], basenames: ["qwen"]),
        ScriptRule(kind: .opencode, pathMarkers: ["opencode-ai/"], basenames: ["opencode"]),
        ScriptRule(kind: .cursor, pathMarkers: ["/cursor-agent/"], basenames: ["cursor-agent"]),
    ]

    static let pythonRules: [ScriptRule] = [
        ScriptRule(kind: .hermes, pathMarkers: [], basenames: ["hermes"]),
        ScriptRule(kind: .aider, pathMarkers: [], basenames: ["aider"]),
    ]

    static let pythonModules: [String: AgentKind] = [
        "hermes_cli.main": .hermes,
        "hermes_cli": .hermes,
        "aider": .aider,
        "aider.main": .aider,
    ]

    // MARK: - Rules

    static func acceptNative(_ kind: AgentKind, rest: [String]) -> Bool {
        if let poison = poisonArgs[kind], rest.contains(where: { arg in poison.contains(where: { has(arg, $0) }) }) {
            return false
        }
        if let sub = firstPositional(rest), let deny = nonSessionSubcommands[kind], deny.contains(sub) {
            return false
        }
        return true
    }

    /// node / bun: the script is the first non-flag argument. Only the script decides the kind,
    /// so `npx @anthropic-ai/claude-code` (script npx-cli.js) is not counted; its child node process is.
    static func classifyScript(_ args: [String], rules: [ScriptRule]) -> AgentKind? {
        guard let idx = scriptIndex(args) else { return nil }
        let script = args[idx]
        let base = stripExtension(basename(script))
        for rule in rules {
            if rule.pathMarkers.contains(where: { has(script, $0) }) || rule.basenames.contains(base) {
                let rest = Array(args[(idx + 1)...])
                return acceptNative(rule.kind, rest: rest) ? rule.kind : nil
            }
        }
        return nil
    }

    static func classifyPython(_ args: [String]) -> AgentKind? {
        // `python -m hermes_cli.main ...` / `python -m aider`
        var i = 1
        while i < args.count {
            let a = args[i]
            if a == "-m", i + 1 < args.count {
                guard let kind = pythonModules[args[i + 1]] else { return nil }
                let rest = Array(args[(i + 2)...])
                return acceptNative(kind, rest: rest) ? kind : nil
            }
            if a == "-c" { return nil }
            if !a.hasPrefix("-") { break }
            i += 1
        }
        if let kind = classifyScript(args, rules: pythonRules) { return kind }
        // Some launchers put the module path somewhere other than first, e.g. runpy wrappers.
        if let idx = args.indices.dropFirst().first(where: { args[$0].hasSuffix("hermes_cli.main") || args[$0].hasSuffix("hermes_cli/main.py") }) {
            return acceptNative(.hermes, rest: Array(args[(idx + 1)...])) ? .hermes : nil
        }
        return nil
    }

    // MARK: - Helpers

    /// Node and Python flags that consume the following argument.
    static let flagsWithValue: Set<String> = [
        "-r", "--require", "--import", "--loader", "--experimental-loader", "-C", "--conditions",
        "--title", "--env-file", "-W", "-X", "--preload",
    ]

    static func scriptIndex(_ args: [String]) -> Int? {
        var i = 1
        while i < args.count {
            let a = args[i]
            if a == "-e" || a == "--eval" || a == "-p" || a == "--print" || a == "-c" { return nil }
            if flagsWithValue.contains(a) { i += 2; continue }
            if a.hasPrefix("-") { i += 1; continue }
            return i
        }
        return nil
    }

    /// First argument that is not a flag. Flags with an inline value (`-c=x`, `--model=x`) are
    /// skipped; a separate flag value may be mistaken for the positional, which only matters if
    /// that value happens to equal a denied subcommand.
    static func firstPositional(_ rest: [String]) -> String? {
        for a in rest {
            if a == "--" { return nil }
            if a.hasPrefix("-") { continue }
            return a
        }
        return nil
    }

    /// Byte-wise substring test. The stdlib's `String.contains(_:)` goes through the generic
    /// string-processing engine and dominated the scan cost; argv is plain UTF-8, so bytes suffice.
    static func has(_ haystack: String, _ needle: String) -> Bool {
        var h = haystack, n = needle
        return h.withUTF8 { hb in
            n.withUTF8 { nb in
                let hc = hb.count, nc = nb.count
                if nc == 0 { return true }
                if nc > hc { return false }
                let first = nb[0]
                var i = 0
                while i <= hc - nc {
                    if hb[i] == first {
                        var j = 1
                        while j < nc && hb[i + j] == nb[j] { j += 1 }
                        if j == nc { return true }
                    }
                    i += 1
                }
                return false
            }
        }
    }

    static func basename(_ path: String) -> String {
        if !path.utf8.contains(UInt8(ascii: "/")) { return path }
        var s = Substring(path)
        while s.hasSuffix("/") { s = s.dropLast() }
        if let slash = s.lastIndex(of: "/") { return String(s[s.index(after: slash)...]) }
        return String(s)
    }

    static func stripExtension(_ name: String) -> String {
        for ext in [".js", ".mjs", ".cjs", ".ts", ".py"] where name.hasSuffix(ext) {
            return String(name.dropLast(ext.count))
        }
        return name
    }
}
