# NOTES: probes session

Branch: `cloud/probes`. Files owned and touched: `Sources/HeadroomMac/*`, `Sources/headroom-cli/main.swift`, this file.
`Sources/HeadroomMac/Placeholder.swift` was deleted.

## What was built

| File | What it does |
|---|---|
| `Sources/HeadroomMac/ProcessProbe.swift` | `ProcessProbe.scan() -> ProcessScan { procs: [ProcInfo], paths: [pid: exec path] }` |
| `Sources/HeadroomMac/MemoryProbe.swift` | `MemoryProbe.read() -> MemoryState` |
| `Sources/HeadroomMac/TerminalProbe.swift` | `TerminalProbe.state(procs:paths:) -> TerminalState` (pure Swift, no Darwin) |
| `Sources/HeadroomMac/LiveProvider.swift` | `public final class LiveProvider` exactly as in OWNERSHIP.md |
| `Sources/headroom-cli/main.swift` | the `headroom` CLI |

Public API beyond OWNERSHIP.md (additive, the app session may use it or ignore it):
`ProcessProbe`, `ProcessScan`, `MemoryProbe`, `TerminalProbe` are all `public`.

### ProcessProbe

Per scan:
1. `proc_listallpids(nil, 0)` for an estimate, then again into a reused `[Int32]` buffer sized estimate + 256.
   The return value is treated as a pid COUNT (libproc divides bytes by `sizeof(int)` for this call).
2. Per pid: `proc_pidinfo(PROC_PIDTBSDINFO)` for `pbi_ppid`, `e_tdev`, `pbi_name`/`pbi_comm`.
   If that fails, falls back to `PROC_PIDT_SHORTBSDINFO` (ppid + comm, no tty). If both fail the pid is skipped.
3. tty: `e_tdev == 0xffffffff` (NODEV) or `0` gives nil; otherwise `devname(dev, S_IFCHR)` ("ttys011"),
   cached per dev number. If devname gives nothing or "??", the tty is named `dev<number>` so it is still counted.
4. Name: basename of `proc_pidpath`, fallback `pbi_name`, then `pbi_comm`.
5. Args (`KERN_PROCARGS2`) only for candidates: basename in {claude, codex, node, bun, deno, hermes, gemini, aider,
   opencode, goose, cursor-agent, amp, copilot, droid, crush, qwen}, or starting with "python" (case-insensitive),
   or a basename that looks like a version ("2.0.14"), or an exec path containing claude/codex/gemini/hermes/aider/
   opencode/cursor-agent/qwen/droid/crush/goose. Buffer size is `KERN_ARGMAX` (fallback 1 MiB), allocated once.
   Parsing is bounds checked everywhere; argc must be in 1..<65536; truncated buffers return what was read.
6. Footprint for every process: `proc_pid_rusage(RUSAGE_INFO_V4).ri_phys_footprint`, fallback
   `PROC_PIDTASKINFO.pti_resident_size`, else 0.

**Name rewrite (assumption, tell core):** the Claude Code native installer runs
`~/.local/share/claude/versions/<version>`, so the exec basename is e.g. `2.0.14`. When the basename looks like a
version and argv is available, `name` becomes the basename of `argv[0]` (normally `claude`). This is the only place
`name` is not the exec basename. Core's classifier should still check `args` as well.

### MemoryProbe

- total: `hw.memsize`
- freePercent: `kern.memorystatus_level`, clamped 0...100
- available: `total * freePercent / 100` (computed without overflow)
- compressed: `host_statistics64(HOST_VM_INFO64).compressor_page_count * vm_kernel_page_size`
  (`mach_host_self()` is taken once per MemoryProbe, not per call, to avoid leaking send rights)
- swap: `vm.swapusage` as `xsw_usage` (`xsu_used`, `xsu_total`)
- pressure: `kern.memorystatus_vm_pressure_level` 1/2/4 -> normal/warning/critical; any failure or other
  value falls back to freePercent <= 15 critical, <= 30 warning, else normal.
- Integer sysctls are read through one helper that accepts 4 or 8 byte results, so it does not matter whether
  the kernel declares a given one as int or int64.

### TerminalProbe

- sessions = distinct non-nil ttys.
- Per tty, the "root" is the process on that tty whose parent is not on the same tty (lowest pid if several;
  this is more robust than plain lowest pid when pids wrap). Its ancestors are walked nearest first
  (max depth 64, cycle safe, stops at pid 1) and the first recognized one wins:
  tmux / zellij / screen, Terminal, iTerm2 (iTerm2, iTermServer*), Ghostty, WezTerm (wezterm*), kitty, Alacritty,
  Warp (anything inside Warp.app, binary "stable"), Hyper, VS Code (Code Helper*, anything inside
  Visual Studio Code.app incl. Electron), Cursor, Zed, Windsurf, ssh (sshd, sshd-session).
- If nothing is recognized: the name of the outermost `.app` bundle of the nearest ancestor that has one
  (so unknown terminals like Tabby or Rio still get a sensible name), else "other".
- The tmux server has no tty, so tmux panes are attributed to tmux because their shell's parent is the server.
  The tty of the window running the tmux CLIENT is attributed to that window's app (Terminal, Ghostty...), since the
  walk starts at the tty's root (login/shell), not at the tmux client.

### LiveProvider

`snapshot()` = one `ProcessProbe.scan()` + `MemoryProbe.read()` + `TerminalProbe.state(...)` on the same scan
+ `Estimator.snapshot(...)`. Not thread safe (buffers are reused); call it from one queue.

### CLI

- `headroom`: headline ("+9 more agents fit", "+1 more agent fits", "+0 more agents fit: do not start another"),
  agents by kind (count, average tree size, total), terminals by app, memory block, method lines.
  Colored only if stdout is a TTY and `NO_COLOR` is unset/empty. Green is #00FF41 via 24-bit escape when
  `COLORTERM` is truecolor/24bit, else ANSI bright green; tight is amber, danger red.
- `--line` prints `Format.line`, `--json` prints `Format.json`, `--watch`/`-w` redraws every 2 s (clear screen,
  hidden cursor, restored on Ctrl-C; when not a TTY it just appends frames). `--watch` combines with
  `--line`/`--json`.
- `--reserve SIZE`, `--per-agent SIZE` (also `--flag=SIZE`). SIZE: bytes or K/M/G/T, optional B/iB, binary units,
  decimals allowed.
- `--per-agent` decision: settings.defaultPerAgentBytes is only used when NO agents run, so setting it alone would
  silently do nothing on a busy Mac. The flag therefore sets the default AND replaces the measured median:
  the CLI recomputes `headroomAgents` and `level` with `Estimator.headroom` / `Estimator.level`.
- `--help`, `--version` (`headroom 0.1.0`). Bad flags exit 2 with usage on stderr.
- On non-macOS the CLI parses flags (help/version work) and then exits 1 with a message.
- The CLI does NOT read the menu bar app's saved settings (the app session owns persistence; no key is defined in
  the contract). It always starts from `HeadroomSettings()` defaults plus flags.

## How this was checked (and what was not)

- The sandbox is Linux. A Swift 6.0.3 Linux toolchain was used to compile everything that is not inside
  `#if os(macOS)`: `TerminalProbe.swift` and `headroom-cli/main.swift` compile cleanly against a STUB HeadroomCore
  (the real core is built on another branch).
- Unit-checked on Linux (scratch harness, not committed): TerminalProbe attribution for Terminal, iTerm2, tmux
  panes, Warp, VS Code, Ghostty + login, Ghostty running tmux client, sshd-session, unknown .app (Tabby), orphan
  tty; `parseProcArgs2` (normal, truncated, no padding, too short, negative argc, empty args, env excluded);
  `wantsArgs`; CLI flag parsing, errors, help, version, and the human render with the author's calibration numbers.
- **None of the Darwin code (ProcessProbe, MemoryProbe, LiveProvider, the macOS branch of main.swift) has been
  compiled.** It was written against the macOS SDK from memory and double checked, but expect possible small
  compile fixes.

## Must verify on a real Mac

1. `swift build` at all. Most likely compile nits, in order of my uncertainty:
   - `devname(dev_t(bitPattern:), S_IFCHR)`: `S_IFCHR` must be `mode_t` (Darwin overlay defines it so).
   - `proc_pid_rusage` buffer type `UnsafeMutablePointer<rusage_info_t?>` via `withMemoryRebound`.
   - `host_statistics64(host, HOST_VM_INFO64, ...)`: flavor type `host_flavor_t` (Int32); `vm_kernel_page_size`
     global availability.
   - `proc_bsdshortinfo` / `PROC_PIDT_SHORTBSDINFO` import names.
2. `PROC_PIDTBSDINFO` for other users' processes: I believe it returns EPERM for root-owned processes when not
   root (hence the SHORTBSDINFO fallback, which loses the tty). Check `headroom --json` tty counts against
   `ps -A -o tty= | sort -u | grep -v '?' | wc -l`. If counts differ a lot, switch the base enumeration to
   `sysctl(CTL_KERN, KERN_PROC, KERN_PROC_ALL)` (one call, `kinfo_proc.kp_eproc.e_ppid` / `e_tdev`, readable for
   all users) and keep libproc only for path/args/footprint.
3. `kern.memorystatus_vm_pressure_level` readable as a normal user (I believe yes). If not, the freePercent
   fallback kicks in silently.
4. `kern.memorystatus_level` equals the "System-wide memory free percentage" printed by `memory_pressure`.
5. Footprint numbers match Activity Monitor's Memory column for claude/codex/hermes.
6. Scan time: `time headroom --json > /dev/null` with ~1500 processes; target < 25 ms for the scan itself
   (process start-up adds a few ms). If slow, the likely cost is `proc_pidpath` for every pid; it could be
   limited to processes whose `pbi_name` is in the candidate set or which turn out to be tty ancestors.
7. devname output is "ttys011" style. The tty count should be close to the author's 131.
8. Claude Code native install: confirm `name` comes out as `claude` (see "Name rewrite" above) and that npm installs
   show as `node` with `cli.js` in args.
9. Terminal attribution on the real machine, especially VS Code (helper names change between versions:
   "Code Helper", "Code Helper (Plugin)"), Warp, and tmux. The `byApp` in `--json` should look plausible.
10. `--watch` Ctrl-C leaves the cursor visible.

## Known gaps / honest caveats

- Not compiled on macOS, not run on macOS, no timing measured. Performance claims are reasoning only.
- Processes owned by other users have no args and footprint 0. Agents always run as the user, so this does not
  affect agent math, but root helpers are not counted anywhere (they are not agents anyway).
- An agent that rewrites its own argv (some python tools via setproctitle) is seen through KERN_PROCARGS2 as the
  rewritten value; the classifier must cope.
- A tty whose only processes are root-owned (e.g. a bare `sudo -s` with no user shell left) is not counted,
  because the SHORTBSDINFO fallback has no tty.
- Version-like name detection (`looksLikeVersion`) accepts digits, dots, dashes and lowercase letters after a
  leading digit; an unrelated binary named like "3proxy" would also get its args read (harmless, slightly slower).
- `TerminalProbe` checks multiplexers per ancestor in walk order, so a tmux server started from inside VS Code's
  terminal still counts its panes as tmux (intended).
- LiveProvider is not thread safe.
- Branch note: the harness for this cloud session designated `claude/macos-probes-qrh8q1`; OWNERSHIP.md says
  `cloud/probes`. The same commits are pushed to both.

## Ready-to-paste snippets

Install the CLI somewhere on PATH first (the ship session's Makefile/installer decides where; examples assume
`/usr/local/bin/headroom`). Use an absolute path: tmux and Claude Code may not see your shell's PATH.

### tmux (`~/.tmux.conf`)

```tmux
set -g status-interval 5
set -g status-right-length 60
set -g status-right '#[fg=#00FF41,bg=#0A0F0A] #(/usr/local/bin/headroom --line) #[default]'
```

Reload with `tmux source-file ~/.tmux.conf`. Output looks like `AG 12 | TTY 31 | 14.2G free | +9`.

### Claude Code statusLine (`~/.claude/settings.json`)

```json
{
  "statusLine": {
    "type": "command",
    "command": "/usr/local/bin/headroom --line",
    "padding": 0
  }
}
```

Claude Code pipes session JSON to the command's stdin; `headroom` ignores stdin, which is fine.
To show it next to an existing status line, call both from a small script, e.g.
`printf '%s | %s' "$(your-old-statusline)" "$(/usr/local/bin/headroom --line)"`.
