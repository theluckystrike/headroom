# Headroom

How many more AI agents can your Mac take? A Matrix-style menu bar meter for agent fleets.

![Headroom in the macOS menu bar on the author's Mac: 37 agents, 144 terminals, 5.2G free, 0 more agents fit, with the dropdown open](docs/screenshot.png)

That is a real capture from my Mac while writing this: 37 agents across 144 terminals, swap 92% full, and Headroom saying stop.

Headroom is a tiny native macOS menu bar app. Swift and AppKit, no dependencies, macOS 13 or later. It counts the AI coding agents you have running, the terminal sessions they live in, and the memory you have left, and turns that into one number: how many more agents fit before the Mac starts swapping hard.

Site: https://theluckystrike.github.io/headroom/

## Why

I run a dozen Claude Code, Codex and Hermes agents at a time, spread across more than 100 terminal tabs, splits and tmux panes. On a 36 GB Mac that works until it does not: memory runs out, swap fills up, everything stalls, and sometimes the machine crashes and takes every session with it.

Activity Monitor can tell you that memory is tight. It cannot tell you whether you can start one more agent. Headroom answers that question at a glance, in the menu bar, every two seconds.

## What it shows

```
AG 12  TTY 31  14.2G  +9
```

| Field | Meaning |
|---|---|
| `AG 12` | Agents running. One agent is one root agent process plus everything it spawned (MCP servers, language servers, shells). |
| `TTY 31` | Terminal sessions. One session is one tty: a tab, a split pane, or a tmux pane. |
| `14.2G` | Available memory, counted the way Activity Monitor counts it: total minus app memory, wired and compressed. |
| `+9` | How many more agents fit before the reserve is hit. This is the number to watch. |

The text sits in neon green `#00FF41` on a near-black pill with faint katakana rain behind it. The level has three states:

- **ok**: 4 or more agents fit.
- **tight**: 1 to 3 fit, or macOS reports warning memory pressure, or swap is 85% or more used.
- **danger**: 0 fit, or macOS reports critical memory pressure, or swap is 85% or more used and the disk has under 10 GB left for swap to grow.

Click the pill for the dropdown: agents per tool with their memory, sessions per terminal app, available memory, swap, pressure, and the per-agent estimate the number is based on.

## Install

Requirements: macOS 13 or later and Xcode Command Line Tools (`xcode-select --install`). The full Xcode app is not needed.

**One-liner**

```sh
curl -fsSL https://raw.githubusercontent.com/theluckystrike/headroom/main/install.sh | bash
```

This builds Headroom from source on your Mac with the Swift compiler that ships with the Command Line Tools. Because the app is built locally, there is no unsigned binary to download and no Gatekeeper prompt. Read [install.sh](install.sh) first if you like; it is short.

**From a clone**

```sh
git clone https://github.com/theluckystrike/headroom && cd headroom && make install
```

Both paths install `Headroom.app` and the `headroom` command line tool.

## The math

Everything comes from counters macOS already keeps.

```
available  = total - (app memory + wired + compressed)      # what Activity Monitor calls free
per_agent  = mean physical footprint of the running agent process trees,
             MCP servers and other children included,
             clamped to [150M, 4G]; 600M when no agents are running
reserve    = 3G by default, doubled while memory pressure is "warning"
headroom   = floor((available - reserve) / per_agent), never below 0; 0 under critical pressure
```

Worked example, measured on my 36 GB Mac on 2026-10-08: app memory 11.6G + wired 3.7G + compressed 13.8G = 29.1G used, so 6.9G available. 37 agents averaged 249M. Pressure was "warning", so the reserve was 6G: floor((6.9 - 6.0) / 0.249) = 3 more agents. A few minutes later available dropped to 5.3G and the answer became 0.

The first version of Headroom used `kern.memorystatus_level`, the figure `memory_pressure` prints. On the same Mac it said 45% free (16.2G) while the compressor held 13.8G of RAM and swap was 91% full, and the estimate came out at +69 agents. That number would have crashed the machine, so Headroom now uses the stricter count.

The reserve covers the OS, your browser, and the bursts agents make when they run tests or builds. The default per-agent cost is only used until at least one agent is running to measure. The reserve, the default per-agent cost and the swap threshold are settings.

## Supported agents

| Agent | Agent | Agent |
|---|---|---|
| Claude Code | Codex | Gemini CLI |
| Hermes | Aider | opencode |
| Goose | Cursor Agent | Amp |
| Copilot CLI | Droid | Crush |
| Qwen Code | | |

Headroom recognizes the root process of an interactive or headless session and folds its whole process tree into one agent. Helpers such as app-server daemons, MCP servers and native messaging hosts are counted inside the agent that started them, not as agents of their own. An agent started by another agent counts as its own agent and is not double counted in its parent's memory.

Missing your agent? Open an issue with the output of `ps -o pid,ppid,comm,args -U $USER | grep <name>` while it runs.

## Terminals

One session is one tty. That means every tab, every split pane and every tmux pane counts as one session, whichever app hosts it. Sessions are grouped by host app in the dropdown:

Terminal, iTerm2, Ghostty, WezTerm, kitty, Alacritty, Warp, VS Code, Cursor, Zed, and tmux.

## CLI

The `headroom` command prints the same numbers in a shell.

```sh
headroom            # human-readable summary
headroom --line     # one line: AG 12 | TTY 31 | 14.2G free | +9
headroom --json     # full snapshot as JSON, for scripts
headroom --watch    # refresh in place every 2 seconds
```

**tmux status bar.** In `~/.tmux.conf`:

```tmux
set -g status-interval 5
set -g status-right '#(headroom --line)'
```

**Claude Code statusLine.** In `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "headroom --line"
  }
}
```

Every Claude Code session then shows the fleet and how many more agents fit, right under the prompt.

## Privacy

- No network access. Headroom does not open a single connection.
- No telemetry, no analytics, no crash reporter.
- It reads only process names, arguments and memory figures of processes owned by your own user, plus system memory counters. It never reads file contents, terminal output or your prompts.

## Performance

- Polls once every 2 seconds. One `sysctl(KERN_PROC_ALL)` call reads the whole process table; argv and executable paths are cached per pid; memory footprints are read only for processes inside agent trees.
- The rain animates at 5 fps (cells snap to whole rows, so more frames add cost, not motion) and pauses in Low Power Mode, while the screen sleeps, and while the menu bar is hidden.
- Measured on an M3 Pro with 1,150 processes and 37 agents: 1.2% of one core with rain off, 1.5 to 1.9% with rain on (about 0.2% of the whole CPU), 14 MB of memory.

## Uninstall

Quit Headroom from its menu, then:

```sh
rm -rf /Applications/Headroom.app ~/Applications/Headroom.app
rm -f /usr/local/bin/headroom ~/.local/bin/headroom
```

If you added it as a login item, remove it in System Settings > General > Login Items. If you used the Claude Code or tmux snippets above, remove those lines too.

## FAQ

**Why not just use Activity Monitor?**
Activity Monitor shows processes, not agents. A single Claude Code session can be a dozen processes: node, several MCP servers, a language server, shells. Activity Monitor also does not know which of your 130 ttys hold agents, and it does not do the division for you. Headroom answers one question, "can I start one more?", without opening a window.

**Why not "free" memory, or `kern.memorystatus_level`?**
Free memory on macOS is close to zero most of the time by design: the kernel keeps file cache around until something needs the space, so it undercounts. `kern.memorystatus_level` overcounts once the compressor is large: on my Mac it said 45% free while the compressor already held 13.8G of RAM and swap was 91% full. Total minus app memory, wired and compressed is the figure Activity Monitor uses, and it stays honest when the compressor is full.

**Why can an agent be more than a process?**
Because an agent is a tree, not a process. Claude Code roots are 120 to 390 MB each on my Mac, but the MCP servers, node and python children they spawn can double or triple that. Headroom measures the whole tree, because the whole tree is what the next agent will cost.

**Is the estimate exact?**
No. It is the mean of what your agents use right now, so it adapts to how you work and heavy sessions pull it up. Agents that start builds or test suites spike above it, which is what the reserve is for. Raise the reserve if you still hit swap.

**Does it work on Intel Macs?**
It should; nothing in it is Apple silicon specific. It is developed and tested on M-series Macs.

## Contributing

Issues and pull requests are welcome. The code is split into small parts:

- `Sources/HeadroomCore`: pure Swift logic (classification, aggregation, the math, formatting). Builds and tests on Linux too: `swift test`.
- `Sources/HeadroomMac`: the macOS probes (libproc, mach, sysctl).
- `Sources/Headroom`: the menu bar app.
- `Sources/headroom-cli`: the `headroom` command.
- `docs/`: this README's images and the website. `python3 docs/make_hero.py` and `python3 docs/make_og.py` regenerate the images.

Adding an agent usually means one rule in the classifier and one test with a real `ps` line. Please keep the app dependency free.

## License

MIT. Copyright (c) 2026 Michael Lip ([github.com/theluckystrike](https://github.com/theluckystrike)). See [LICENSE](LICENSE).
