# NOTES-core

Session: core. Branch: `cloud/core`.

## What I built

- `Sources/HeadroomCore/AgentClassifier.swift`: `AgentClassifier.classify(_:) -> AgentKind?`
- `Sources/HeadroomCore/Aggregator.swift`: `Aggregator.agents(from:) -> [AgentInstance]`
- `Sources/HeadroomCore/Estimator.swift`: `perAgentBytes`, `headroom`, `level`, `snapshot`, plus the public
  constants `Estimator.minPerAgentBytes` (150 MiB) and `Estimator.maxPerAgentBytes` (4 GiB)
- `Sources/HeadroomCore/Format.swift`: `bytes`, `line`, `json`
- `Sources/HeadroomCore/Fixtures.swift`: `Fixtures.demo`
- Deleted `Sources/HeadroomCore/Placeholder.swift` and `Tests/HeadroomCoreTests/PlaceholderTests.swift`.
- Tests: 67 XCTest cases in `Tests/HeadroomCoreTests` (classifier, aggregator, estimator, format, fixtures,
  substring helper). All pass.

All public signatures match OWNERSHIP.md exactly. `Model.swift` is untouched. Only `Format.swift` imports
Foundation (for `String(format:)` and `JSONEncoder`); everything else is plain stdlib.

## How it was tested (be aware)

- Toolchain: swift.org tarball, Swift 6.0.3 for Ubuntu 24.04, unpacked into the session scratchpad (not the repo).
- `swift build --target HeadroomCore` in the repo: passes.
- `swift build --target HeadroomCoreTests` in the repo: passes.
- `swift test --filter HeadroomCoreTests` in the repo does NOT work on Linux. SwiftPM builds every target
  first, and `Sources/Headroom/main.swift` imports AppKit. That is expected.
- So I ran the tests from a scratch package outside the repo. It copies `Sources/HeadroomCore` and
  `Tests/HeadroomCoreTests` and has a Package.swift with just those two targets. Result: 67 tests, 0 failures,
  in debug and in release.
- I have not run anything on macOS. Run `swift test --filter HeadroomCoreTests` on a Mac.

## Classifier rules as implemented

Matching uses the basename of `ProcInfo.name` (case-sensitive for native binaries) plus argv.

- Native binaries, exact basename: `claude`, `codex`, `gemini`, `hermes`, `aider`, `opencode`, `goose`,
  `cursor-agent`, `amp`, `copilot`, `droid`, `crush`, `qwen`. `Claude` (capital C) is the desktop app and is
  not matched.
- `node` / `bun` / `nodejs`: the kind comes from the SCRIPT argument only. The script is the first argument
  that is not a flag; flags that take a value (`-r`, `--require`, `--import`, ...) are skipped. `-e`, `-p` and
  `-c` mean there is no script. A script matches when its path contains a package marker
  (`@anthropic-ai/claude-code/`, `claude-code/cli.js`, `@openai/codex/`, `@google/gemini-cli/`,
  `@sourcegraph/amp/`, `@github/copilot/`, `@qwen-code/`, `opencode-ai/`, `/cursor-agent/`) or when its
  basename, minus the extension, is the agent name. The basename rule covers shebang launches like
  `node /opt/homebrew/bin/claude`, where argv[1] is the symlink and not the package path.
- `python*` (any case, e.g. `Python`, `python3.12`): `-m hermes_cli.main`, `-m hermes_cli`, `-m aider`,
  `-m aider.main`, a script whose basename is `hermes` or `aider`, or an argument ending in `hermes_cli.main`
  or `hermes_cli/main.py`.
- Exclusions:
  - argv[0] contains `/Claude.app/`.
  - Any arg contains `chrome-native-host`.
  - Per-kind denied subcommands, checked against the first positional argument:
    - codex: `app-server`, `mcp-server`, `mcp`, `proto`, `login`, `logout`, `completion`, `debug`, `sandbox`, `apply`
    - claude: `mcp`, `update`, `doctor`, `install`, `setup-token`, `migrate-installer`
    - hermes: `gateway`, `modellock`
    - goose: `mcp`, `configure`, `info`, `update`, `version`, `help`, `web`, `serve`
    - a few more for gemini, opencode, amp, copilot and qwen
  - Poison args anywhere in argv: codex `pid-update-loop`, `app-server`, `codex-code-mode-host`; hermes `modellock`.
- Shells, tmux, screen, env and similar never match. They fail the first gate (not a native agent name, not
  node or bun, not python), so `zsh -c "... claude ..."` and `tmux new-session ... claude` are never agents.
- `@github/copilot-language-server` (the editor LSP) is deliberately NOT Copilot CLI. The marker has a
  trailing slash.
- `npx @anthropic-ai/claude-code`: the npx process is not counted because its script is `npx-cli.js`. The
  child node running `cli.js` is counted.

## Deviations from the spec / decisions I made

1. **Same-kind direct child is folded into its parent.** OWNERSHIP says a descendant agent is a separate
   instance. I follow that, with one exception: a process classified as the same kind as its DIRECT parent
   is folded into the parent's tree. The npm-installed codex (`node .../codex.js`, which spawns the native
   `codex`) and gemini-cli's self-relaunch with a bigger heap would otherwise show up as two agents. An agent
   started from another agent's shell tool has a shell in between, so it still counts separately. If the
   app/probes sessions disagree, delete the folding: `isFolded` and the `kc != kinds[i]` condition in
   `Aggregator.swift`.
2. **Cycles.** The pass-1 roots are classified, non-folded processes. A ppid cycle made only of same-kind
   agents has no such root. Pass 2 then makes the first unvisited one in input order the root, so the session
   does not vanish. Every process is counted at most once.
3. **Duplicate pids** in one scan: the first entry wins and later duplicates are ignored completely (not
   counted, no tree edges).
4. **Even-count median** is the mean of the two middle values, using integer math that cannot overflow.
5. **`headroom` with perAgentBytes == 0** divides by 1 instead of trapping. This cannot happen through
   `snapshot` because of the clamp.
6. **`level`**: danger if headroom <= 0, or pressure is critical, or swapUsed/swapTotal >= swapDangerRatio
   (only when swapTotal > 0). tight if headroom <= 3 or pressure is warning. Otherwise ok. Danger wins over
   warning.
7. **`Format.bytes`**: below 1024 it prints raw bytes (`0B`, `512B`). From 1 K up it uses binary units
   K/M/G/T/P/E with one decimal when the value rounds below 100, and whole numbers from 100 up. A value that
   rounds to 1024 of a unit is promoted (`1023.98M` -> `1.0G`). It uses `String(format:)` with no locale,
   so the decimal separator is always `.`.
8. **`Format.json`** returns `"{}"` if encoding fails. It cannot fail for this model.
9. **`Fixtures.demo`**: perAgentBytes, headroom and level are computed with the Estimator from fixed agent
   trees, so the demo can never disagree with the real math.
   - Median tree is 1175 MiB, and available is 14541 MiB ("14.2G"). (14541 - 3072) / 1175 = 9.76, so +9.
   - Terminals are 9 in Terminal, 14 in iTerm2 and 8 in tmux.
   - takenAt is fixed at 1791460800.
   - The per-agent trees (260 MiB to 2.3 GiB) are larger than the author's measured root processes. This is
     on purpose: they include MCP servers and node children, and they were needed to hit the requested +9.
10. **Performance.** The stdlib's `String.contains(String)` turned out to be the main cost of a scan. I
    replaced it with a byte-wise search (`AgentClassifier.has`). Release build, x86_64 Linux container:
    classify for 1500 processes is about 1.3 ms, and the full `Aggregator.agents` is about 1.5 ms. A 200k
    process 50k-deep chain is handled iteratively, with no recursion.

## Must be verified on a real Mac

- **Process names.** What `ProcInfo.name` actually holds for each agent, from the probes session's
  `proc_name` / `p_comm`:
  - Interpreted scripts: is `p_comm` the interpreter (`node`, `Python`) or the script name? I handle both
    (native name and interpreter + script).
  - `p_comm` is truncated to 16 chars (MAXCOMLEN). `cursor-agent` is 12 chars, so it fits. A longer name
    would need the probes to use the argv[0] basename.
  - Bun-compiled Claude Code: confirm it appears as `claude`.
- **Codex.**
  - Confirm `codex app-server` is the only daemon form the Codex desktop app runs.
  - Confirm `pid-update-loop` shows up in argv the way I assumed: as an arg containing that string.
- **Hermes.**
  - Confirm the exact argv of the `gateway run` daemon and of `modellock`.
  - Confirm whether interactive Hermes is `python .../bin/hermes chat` or something else.
- **Claude Desktop.** Desktop-launched Claude Code sessions live under
  `~/Library/Application Support/Claude/claude-code/...`, not under Claude.app, so they ARE counted as agents.
  I think that is correct, but confirm.
- **Hermes name clash.** `hermes` is also the name of Meta's JavaScript engine CLI (React Native). It is
  short-lived, so it is unlikely to matter.
- **The fold heuristic.** Check it against a real npm-installed codex and gemini-cli process tree.
- **Real tests.** Run `swift test --filter HeadroomCoreTests` on macOS. It should be green; the code uses no
  platform APIs.

## Known gaps

- **pid reuse** cannot be detected without process start times, which `ProcInfo` does not carry. A reused
  ppid can attribute a process to the wrong tree. It never crashes or double counts. Adding `startTime` to
  `ProcInfo` would fix this, but that is a Model.swift change and needs to go through the owner.
- **Empty argv** (other users' processes): node/python agents cannot be identified. Native-named ones still
  can.
- **Flag values.** The first-positional subcommand check can mistake a flag's separate value for a
  subcommand, e.g. `codex -c mcp`. It only matters if that value equals a denied subcommand word.
- **Missing agents.** Agents not in `AgentKind` (Cline, Continue CLI, Kiro, etc.) are not recognized. Adding
  them needs a Model.swift change.
- **Linux test run.** The full package test command does not run on Linux, as explained above. CI on macOS
  should run `swift test`.
- **Branches.** This cloud session was also given a harness branch named `claude/headroom-core-f5t53t`.
  Following OWNERSHIP.md and the session instructions, the work is pushed to `cloud/core`, and the same
  commits are mirrored to the harness branch.
