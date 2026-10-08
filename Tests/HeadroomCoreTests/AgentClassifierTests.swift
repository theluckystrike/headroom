import XCTest
@testable import HeadroomCore

final class AgentClassifierTests: XCTestCase {
    // MARK: Claude Code

    func testClaudeNativeBinary() {
        XCTAssertEqual(kind(["/Users/x/.local/bin/claude", "--resume", "abc"]), .claude)
        XCTAssertEqual(kind(["claude"]), .claude)
        XCTAssertEqual(kind(["claude", "-p", "fix the tests", "--output-format", "json"]), .claude)
        XCTAssertEqual(kind(["claude", "update the readme"]), .claude, "a prompt is not a subcommand")
    }

    func testClaudeWithUnreadableArgs() {
        XCTAssertEqual(kind([], name: "claude"), .claude)
    }

    func testClaudeViaNode() {
        XCTAssertEqual(kind(["node", "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js"]), .claude)
        XCTAssertEqual(kind(["node", "--max-old-space-size=8192", "/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js", "--continue"]), .claude)
        XCTAssertEqual(kind(["/Users/x/.bun/bin/bun", "/Users/x/src/claude-code/cli.js"]), .claude)
        // Shebang launch: argv[1] is the symlink, not the package path.
        XCTAssertEqual(kind(["node", "/opt/homebrew/bin/claude", "--resume"]), .claude)
    }

    func testClaudeDesktopAppIsNotAnAgent() {
        XCTAssertNil(kind(["/Applications/Claude.app/Contents/MacOS/Claude"]))
        XCTAssertNil(kind(["/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper", "--type=renderer"]))
        XCTAssertNil(kind(["/Applications/Claude.app/Contents/Helpers/chrome-native-host"]))
        XCTAssertNil(kind(["/Applications/Claude.app/Contents/Resources/claude"], name: "claude"))
        XCTAssertNil(kind(["Claude"], name: "Claude"), "capital-C Claude is the desktop app")
    }

    func testClaudeHelpersAreNotAgents() {
        XCTAssertNil(kind(["claude", "--chrome-native-host"]))
        XCTAssertNil(kind(["claude", "mcp", "serve"]))
        XCTAssertNil(kind(["claude", "update"]))
        XCTAssertNil(kind(["claude", "doctor"]))
    }

    func testNpxLauncherIsNotTheAgent() {
        // `npx @anthropic-ai/claude-code`: the npx process only installs and spawns the real cli.js.
        XCTAssertNil(kind(["node", "/opt/homebrew/lib/node_modules/npm/bin/npx-cli.js", "@anthropic-ai/claude-code"]))
    }

    func testUnrelatedNodeIsNotAnAgent() {
        XCTAssertNil(kind(["node", "/Users/x/proj/node_modules/.bin/vite"]))
        XCTAssertNil(kind(["node", "-e", "require('@anthropic-ai/claude-code')"]))
        XCTAssertNil(kind(["node"]))
        XCTAssertNil(kind(["node", "/Users/x/.npm/_npx/1/node_modules/@modelcontextprotocol/server-filesystem/dist/index.js"]))
    }

    // MARK: Codex

    func testCodexNative() {
        XCTAssertEqual(kind(["/opt/homebrew/bin/codex"]), .codex)
        XCTAssertEqual(kind(["codex", "resume", "0199a3c2-1111"]), .codex)
        XCTAssertEqual(kind(["codex", "exec", "--full-auto", "run the tests"]), .codex)
        XCTAssertEqual(kind(["codex", "-m", "gpt-5-codex", "write docs"]), .codex)
    }

    func testCodexHelpersAreNotAgents() {
        XCTAssertNil(kind(["/Applications/Codex.app/Contents/Resources/codex", "app-server", "--analytics-default-enabled"]))
        XCTAssertNil(kind(["codex", "app-server"]))
        XCTAssertNil(kind(["codex", "mcp-server"]))
        XCTAssertNil(kind(["/Users/x/.codex/bin/codex-code-mode-host", "--port", "0"]))
        XCTAssertNil(kind(["codex", "--pid-update-loop", "4242"]))
        XCTAssertNil(kind(["codex", "internal", "pid-update-loop"]))
    }

    func testCodexViaNode() {
        XCTAssertEqual(kind(["node", "/opt/homebrew/lib/node_modules/@openai/codex/bin/codex.js"]), .codex)
        XCTAssertEqual(kind(["node", "/opt/homebrew/bin/codex", "resume", "--last"]), .codex)
        XCTAssertNil(kind(["node", "/opt/homebrew/lib/node_modules/@openai/codex/bin/codex.js", "app-server"]))
    }

    // MARK: Hermes

    func testHermesPython() {
        XCTAssertEqual(kind(["/Users/x/.hermes/venv/bin/python3", "/Users/x/.local/bin/hermes", "chat"], name: "python3.11"), .hermes)
        XCTAssertEqual(kind(["/Library/Frameworks/Python.framework/Versions/3.12/Resources/Python.app/Contents/MacOS/Python", "/usr/local/bin/hermes"], name: "Python"), .hermes)
        XCTAssertEqual(kind(["python", "-m", "hermes_cli.main", "chat"]), .hermes)
        XCTAssertEqual(kind(["python3", "-u", "/Users/x/hermes/hermes_cli/main.py"]), .hermes)
        XCTAssertEqual(kind(["hermes", "chat"]), .hermes)
    }

    func testHermesDaemonsAreNotAgents() {
        XCTAssertNil(kind(["python3", "/Users/x/.local/bin/hermes", "gateway", "run"], name: "python3.11"))
        XCTAssertNil(kind(["python3", "-m", "hermes_cli.main", "gateway", "run"]))
        XCTAssertNil(kind(["hermes", "gateway", "run"]))
        XCTAssertNil(kind(["python3", "/Users/x/.local/bin/hermes", "modellock"], name: "python3.11"))
        XCTAssertNil(kind(["python3", "/Users/x/.hermes/modellock.py"], name: "python3.11"))
        XCTAssertNil(kind(["python3", "/Users/x/proj/hermes_utils.py"]))
        XCTAssertNil(kind(["python3", "-c", "import hermes_cli.main"]))
    }

    // MARK: Other agents

    func testGemini() {
        XCTAssertEqual(kind(["gemini"]), .gemini)
        XCTAssertEqual(kind(["node", "/opt/homebrew/lib/node_modules/@google/gemini-cli/dist/index.js"]), .gemini)
        XCTAssertEqual(kind(["node", "--max-old-space-size=16384", "/opt/homebrew/bin/gemini"]), .gemini)
    }

    func testAider() {
        XCTAssertEqual(kind(["aider", "--model", "sonnet"]), .aider)
        XCTAssertEqual(kind(["/Users/x/.local/pipx/venvs/aider-chat/bin/python", "/Users/x/.local/bin/aider"], name: "python3.12"), .aider)
        XCTAssertEqual(kind(["python3", "-m", "aider"]), .aider)
        XCTAssertNil(kind(["python3", "/Users/x/proj/aider_helpers.py"]))
    }

    func testOpencode() {
        XCTAssertEqual(kind(["opencode"]), .opencode)
        XCTAssertEqual(kind(["/Users/x/.opencode/bin/opencode", "run", "hello"]), .opencode)
        XCTAssertNil(kind(["opencode", "auth", "login"]))
    }

    func testGoose() {
        XCTAssertEqual(kind(["goose", "session"]), .goose)
        XCTAssertEqual(kind(["goose", "run", "-t", "hi"]), .goose)
        XCTAssertNil(kind(["goosed", "agent"]), "goosed is the desktop server")
        XCTAssertNil(kind(["goose", "mcp", "developer"]), "goose mcp is an extension server")
        XCTAssertNil(kind(["goose", "configure"]))
    }

    func testCursorAgent() {
        XCTAssertEqual(kind(["cursor-agent"]), .cursor)
        XCTAssertEqual(kind(["/Users/x/.local/bin/cursor-agent", "--resume"]), .cursor)
        XCTAssertNil(kind(["/Applications/Cursor.app/Contents/MacOS/Cursor"]))
    }

    func testAmp() {
        XCTAssertEqual(kind(["amp"]), .amp)
        XCTAssertEqual(kind(["node", "/opt/homebrew/lib/node_modules/@sourcegraph/amp/dist/main.js"]), .amp)
    }

    func testCopilot() {
        XCTAssertEqual(kind(["copilot"]), .copilot)
        XCTAssertEqual(kind(["node", "/opt/homebrew/lib/node_modules/@github/copilot/index.js"]), .copilot)
        XCTAssertNil(kind(["node", "/Users/x/.vscode/extensions/github.copilot/node_modules/@github/copilot-language-server/dist/language-server.js", "--stdio"]),
                     "the editor language server is not the CLI")
    }

    func testDroidCrushQwen() {
        XCTAssertEqual(kind(["droid"]), .droid)
        XCTAssertEqual(kind(["/Users/x/.local/bin/crush"]), .crush)
        XCTAssertEqual(kind(["qwen"]), .qwen)
        XCTAssertEqual(kind(["node", "/opt/homebrew/lib/node_modules/@qwen-code/qwen-code/cli.js"]), .qwen)
    }

    // MARK: Wrappers

    func testShellWrappersAreNotAgents() {
        XCTAssertNil(kind(["/bin/zsh", "-c", "cd ~/proj && claude --resume"]))
        XCTAssertNil(kind(["bash", "-c", "source venv/bin/activate && hermes chat"]))
        XCTAssertNil(kind(["-zsh"], name: "zsh"))
        XCTAssertNil(kind(["sh", "-c", "codex exec 'run tests'"]))
        XCTAssertNil(kind(["fish", "-c", "gemini"]))
        XCTAssertNil(kind(["tmux", "new-session", "-d", "-s", "work", "claude"]))
        XCTAssertNil(kind(["screen", "-dmS", "a", "codex"]))
        XCTAssertNil(kind(["env", "FOO=1", "claude"]))
    }

    func testNameMatchingIsExact() {
        XCTAssertNil(kind(["claude-helper"]))
        XCTAssertNil(kind(["codexbar"]))
        XCTAssertNil(kind(["xamp"]))
        XCTAssertNil(kind([""], name: ""))
        XCTAssertNil(kind(["rg", "claude"]))
        XCTAssertNil(kind(["grep", "codex"]))
    }

    func testEveryKindIsReachable() {
        let samples: [AgentKind: [String]] = [
            .claude: ["claude"], .codex: ["codex"], .gemini: ["gemini"], .hermes: ["hermes"], .aider: ["aider"],
            .opencode: ["opencode"], .goose: ["goose"], .cursor: ["cursor-agent"], .amp: ["amp"],
            .copilot: ["copilot"], .droid: ["droid"], .crush: ["crush"], .qwen: ["qwen"],
        ]
        for k in AgentKind.allCases {
            XCTAssertEqual(kind(samples[k] ?? []), k, "\(k)")
        }
    }

    func testBasename() {
        XCTAssertEqual(AgentClassifier.basename("/a/b/c"), "c")
        XCTAssertEqual(AgentClassifier.basename("c"), "c")
        XCTAssertEqual(AgentClassifier.basename("/a/b/"), "b")
        XCTAssertEqual(AgentClassifier.basename(""), "")
    }
}
