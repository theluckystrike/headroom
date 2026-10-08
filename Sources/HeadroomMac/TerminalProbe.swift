import HeadroomCore

// Pure Swift on purpose (no Darwin calls): it only reasons over a process list, so it builds anywhere.

/// Counts terminal sessions (distinct ttys) and attributes each one to the app hosting it.
public enum TerminalProbe {
    /// - Parameters:
    ///   - procs: one process table scan.
    ///   - paths: executable path per pid (optional); lets generic binary names ("stable", "Electron")
    ///     be recognized by their app bundle.
    public static func state(procs: [ProcInfo], paths: [Int32: String] = [:]) -> TerminalState {
        var byPid: [Int32: ProcInfo] = [:]
        byPid.reserveCapacity(procs.count)
        for p in procs { byPid[p.pid] = p }

        var byTty: [String: [ProcInfo]] = [:]
        for p in procs {
            if let tty = p.tty { byTty[tty, default: []].append(p) }
        }

        var byApp: [String: Int] = [:]
        for (tty, members) in byTty {
            let app = hostApp(tty: tty, members: members, byPid: byPid, paths: paths)
            byApp[app, default: 0] += 1
        }
        return TerminalState(sessions: byTty.count, byApp: byApp)
    }

    /// The tty's root is the process on it whose parent is not on the same tty (normally `login`
    /// or the shell). Its ancestors, nearest first, are checked against the known hosts.
    static func hostApp(tty: String, members: [ProcInfo], byPid: [Int32: ProcInfo], paths: [Int32: String]) -> String {
        let roots = members.filter { byPid[$0.ppid]?.tty != tty }
        guard let root = (roots.isEmpty ? members : roots).min(by: { $0.pid < $1.pid }) else { return "other" }

        var bundleFallback: String? = nil
        var visited: Set<Int32> = [root.pid]
        var pid = root.ppid
        var depth = 0
        while pid > 1, depth < 64, !visited.contains(pid), let p = byPid[pid] {
            visited.insert(pid)
            depth += 1
            let path = paths[pid]
            if let app = recognize(name: p.name, path: path) { return app }
            if bundleFallback == nil, let path, let bundle = outermostBundle(path) { bundleFallback = bundle }
            pid = p.ppid
        }
        return bundleFallback ?? "other"
    }

    /// Maps one ancestor to a host app name, or nil when it is not a known terminal host.
    static func recognize(name: String, path: String?) -> String? {
        let n = name.lowercased()
        let bundle = path.flatMap(outermostBundle)?.lowercased()

        // Multiplexers first: a pane inside tmux counts as tmux whatever window tmux runs in.
        // The tmux server has no tty, so it is only ever reached as an ancestor.
        if n == "tmux" || n.hasPrefix("tmux:") { return "tmux" }
        if n == "zellij" { return "zellij" }
        if n == "screen" { return "screen" }

        if n == "terminal" || bundle == "terminal" { return "Terminal" }
        if n == "iterm2" || n.hasPrefix("itermserver") || bundle == "iterm" || bundle == "iterm2" { return "iTerm2" }
        if n == "ghostty" || bundle == "ghostty" { return "Ghostty" }
        if n.hasPrefix("wezterm") || bundle == "wezterm" { return "WezTerm" }
        if n == "kitty" || bundle == "kitty" { return "kitty" }
        if n == "alacritty" || bundle == "alacritty" { return "Alacritty" }
        if n == "warp" || bundle == "warp" || bundle?.hasPrefix("warp") == true { return "Warp" }
        if n == "hyper" || bundle == "hyper" { return "Hyper" }
        if bundle == "visual studio code" || bundle == "visual studio code - insiders" || n.hasPrefix("code helper")
            || n == "code" { return "VS Code" }
        if bundle == "cursor" || n == "cursor" || n.hasPrefix("cursor helper") { return "Cursor" }
        if bundle == "zed" || bundle == "zed preview" || n == "zed" { return "Zed" }
        if bundle == "windsurf" || n.hasPrefix("windsurf") { return "Windsurf" }
        if n == "sshd" || n.hasPrefix("sshd-") || n == "sshd-session" { return "ssh" }
        return nil
    }

    /// "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper"
    /// -> "Visual Studio Code". The outermost bundle names the app the user launched.
    static func outermostBundle(_ path: String) -> String? {
        for component in path.split(separator: "/") where component.hasSuffix(".app") {
            let name = component.dropLast(4)
            return name.isEmpty ? nil : String(name)
        }
        return nil
    }
}
