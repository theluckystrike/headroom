#if os(macOS)
import Darwin
import HeadroomCore

/// Result of one process table scan.
public struct ProcessScan: Sendable {
    /// Every process the probe could see (other users' processes included, usually without args or footprint).
    public var procs: [ProcInfo]
    /// Full executable path per pid, when proc_pidpath succeeded. Used by TerminalProbe to recognize
    /// app bundles ("/Applications/Warp.app/...") whose binaries have generic names ("stable", "Electron").
    public var paths: [Int32: String]
}

/// Enumerates processes through libproc and sysctl.
///
/// Not thread safe: it reuses buffers between scans. Use one instance per thread (LiveProvider owns one).
public final class ProcessProbe {
    /// Executable basenames (lowercased) whose argv we read. Everything else gets `args == []`,
    /// which keeps a full scan cheap: KERN_PROCARGS2 is the most expensive call per process.
    static let argCandidates: Set<String> = [
        "claude", "codex", "node", "bun", "deno", "hermes", "gemini", "aider", "opencode", "goose",
        "cursor-agent", "amp", "copilot", "droid", "crush", "qwen",
    ]
    /// Distinctive substrings of a lowercased executable path that also trigger an argv read. Catches
    /// native installs whose binary is named after its version, e.g. ~/.local/share/claude/versions/2.0.14.
    static let argPathTokens: [String] = [
        "claude", "codex", "gemini", "hermes", "aider", "opencode", "cursor-agent", "qwen", "droid",
        "crush", "goose",
    ]

    private var pidBuffer: [Int32] = []
    private var pathBuffer = [UInt8](repeating: 0, count: 4 * 1024) // PROC_PIDPATHINFO_MAXSIZE = 4 * MAXPATHLEN
    private var argsBuffer: [UInt8] = []
    private var ttyNames: [UInt32: String] = [:]

    public init() {
        argsBuffer = [UInt8](repeating: 0, count: ProcessProbe.argMax())
    }

    /// One pass over the process table.
    public func scan() -> ProcessScan {
        let pids = listPids()
        var procs: [ProcInfo] = []
        procs.reserveCapacity(pids.count)
        var paths: [Int32: String] = [:]
        paths.reserveCapacity(pids.count)

        for pid in pids where pid > 0 {
            guard let bsd = bsdInfo(pid) else { continue } // exited, or not visible at all
            let path = executablePath(pid)
            if let path { paths[pid] = path }

            var name = path.map(baseName) ?? ""
            if name.isEmpty { name = bsd.name }
            if name.isEmpty { continue }

            var args: [String] = []
            if ProcessProbe.wantsArgs(name: name, path: path) {
                args = arguments(pid)
                // Native installs run a binary named after its version ("2.0.14"); argv[0] says what it is.
                if ProcessProbe.looksLikeVersion(name), let first = args.first {
                    let argv0 = baseName(first)
                    if !argv0.isEmpty { name = argv0 }
                }
            }

            procs.append(ProcInfo(pid: pid, ppid: bsd.ppid, tty: bsd.tty, name: name, args: args,
                                  footprintBytes: footprint(pid)))
        }
        return ProcessScan(procs: procs, paths: paths)
    }

    // MARK: - pids

    private func listPids() -> [Int32] {
        // With a NULL buffer proc_listallpids returns the current number of pids.
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        let capacity = Int(estimate) + 256 // processes spawned between the two calls
        if pidBuffer.count < capacity {
            pidBuffer = [Int32](repeating: 0, count: capacity)
        }
        let byteSize = Int32(pidBuffer.count * MemoryLayout<Int32>.stride)
        // Returns the number of pids written (not bytes).
        let count = pidBuffer.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, byteSize) }
        guard count > 0 else { return [] }
        return Array(pidBuffer.prefix(min(Int(count), pidBuffer.count)))
    }

    // MARK: - BSD info (ppid, tty, name)

    private struct Bsd {
        var ppid: Int32
        var tty: String?
        var name: String
    }

    private func bsdInfo(_ pid: Int32) -> Bsd? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size {
            var name = ProcessProbe.cString(info.pbi_name)
            if name.isEmpty { name = ProcessProbe.cString(info.pbi_comm) }
            return Bsd(ppid: Int32(bitPattern: info.pbi_ppid), tty: ttyName(info.e_tdev), name: name)
        }
        // PROC_PIDTBSDINFO is refused for other users' processes (root owned login, sshd, launchd).
        // The short variant is not, and still gives the ppid, which TerminalProbe needs to walk ancestry.
        var short = proc_bsdshortinfo()
        let shortSize = Int32(MemoryLayout<proc_bsdshortinfo>.stride)
        if proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &short, shortSize) == shortSize {
            return Bsd(ppid: Int32(bitPattern: short.pbi_ppid), tty: nil, name: ProcessProbe.cString(short.pbi_comm))
        }
        return nil
    }

    private func ttyName(_ dev: UInt32) -> String? {
        // NODEV is (dev_t)-1; 0 also means "no controlling terminal" in practice.
        if dev == UInt32.max || dev == 0 { return nil }
        if let cached = ttyNames[dev] { return cached }
        // Still a terminal when devname fails; a stable synthetic name keeps it counted once.
        var result = "dev\(dev)"
        if let p = devname(dev_t(bitPattern: dev), S_IFCHR) {
            let s = String(cString: p)
            // devname returns "??" (or "#C<maj>:<min>" on some versions) when /dev has no node for it.
            if !s.isEmpty && s != "??" { result = s }
        }
        ttyNames[dev] = result
        return result
    }

    // MARK: - path and args

    private func executablePath(_ pid: Int32) -> String? {
        let n = pathBuffer.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
        guard n > 0 else { return nil }
        let len = min(Int(n), pathBuffer.count)
        return String(decoding: pathBuffer[0..<len], as: UTF8.self)
    }

    static func wantsArgs(name: String, path: String?) -> Bool {
        let lower = name.lowercased()
        if argCandidates.contains(lower) || lower.hasPrefix("python") { return true }
        if looksLikeVersion(name) { return true }
        if let path {
            let lp = path.lowercased()
            for token in argPathTokens where lp.contains(token) { return true }
        }
        return false
    }

    static func looksLikeVersion(_ s: String) -> Bool {
        guard let first = s.unicodeScalars.first, ("0"..."9").contains(first) else { return false }
        return s.unicodeScalars.allSatisfy { ("0"..."9").contains($0) || $0 == "." || $0 == "-" || ("a"..."z").contains($0) }
    }

    private func arguments(_ pid: Int32) -> [String] {
        guard !argsBuffer.isEmpty else { return [] }
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = argsBuffer.count
        let rc = argsBuffer.withUnsafeMutableBytes { buf in
            sysctl(&mib, u_int(mib.count), buf.baseAddress, &size, nil, 0)
        }
        guard rc == 0 else { return [] } // other users' processes: EINVAL / EPERM
        return argsBuffer.withUnsafeBytes { ProcessProbe.parseProcArgs2(UnsafeRawBufferPointer(rebasing: $0[0..<min(size, $0.count)])) }
    }

    /// Parses a KERN_PROCARGS2 buffer: [int32 argc][exec path\0][\0 padding][argv[0]\0]...[argv[argc-1]\0][env...].
    /// Every read is bounds checked; a truncated buffer yields the args read so far.
    static func parseProcArgs2(_ buf: UnsafeRawBufferPointer) -> [String] {
        let n = buf.count
        guard n >= MemoryLayout<Int32>.size else { return [] }
        var argcRaw: Int32 = 0
        withUnsafeMutableBytes(of: &argcRaw) { dst in
            for i in 0..<MemoryLayout<Int32>.size { dst[i] = buf[i] }
        }
        let argc = Int(argcRaw)
        guard argc > 0 && argc < 65_536 else { return [] }

        var pos = MemoryLayout<Int32>.size
        while pos < n && buf[pos] != 0 { pos += 1 } // exec path
        while pos < n && buf[pos] == 0 { pos += 1 } // padding

        var args: [String] = []
        args.reserveCapacity(min(argc, 64))
        while args.count < argc && pos < n {
            let start = pos
            while pos < n && buf[pos] != 0 { pos += 1 }
            args.append(String(decoding: UnsafeRawBufferPointer(rebasing: buf[start..<pos]), as: UTF8.self))
            pos += 1 // skip the NUL (may step past n, loop condition handles it)
        }
        return args
    }

    static func argMax() -> Int {
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctl(&mib, u_int(mib.count), &value, &size, nil, 0) == 0 && value > 0 {
            return Int(value)
        }
        return 1 << 20
    }

    // MARK: - memory

    private func footprint(_ pid: Int32) -> UInt64 {
        var usage = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &usage) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        if rc == 0 { return usage.ri_phys_footprint }

        var task = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, size) == size {
            return task.pti_resident_size
        }
        return 0 // other users' processes
    }

    // MARK: - helpers

    /// Reads a fixed size C char array (imported as a tuple) up to the first NUL or its end.
    static func cString<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in
            let end = raw.firstIndex(of: 0) ?? raw.count
            return String(decoding: UnsafeRawBufferPointer(rebasing: raw[0..<end]), as: UTF8.self)
        }
    }
}

func baseName(_ path: String) -> String {
    guard let slash = path.lastIndex(of: "/") else { return path }
    return String(path[path.index(after: slash)...])
}
#endif
