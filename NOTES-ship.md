# NOTES-ship

Session: ship. Owns Makefile, scripts/, .github/, Resources/, install.sh, uninstall.sh, this file.
Pushed to `cloud/ship` (as the brief asked) and to `claude/headroom-packaging-ci-iep3jz` (the branch this
cloud session was assigned). Both point at the same commits.

Everything here was written and tested on **Linux**. No macOS, no Xcode, no `swift build` of the app or
CLI, no `codesign`, no `iconutil` was ever run for real. Read the "must verify on a real Mac" list before
trusting any of it.

## What I built

| Path | What it does |
|---|---|
| `Resources/Info.plist` | Bundle id `io.github.theluckystrike.headroom`, name/executable `Headroom`, 0.1.0 (1), `LSUIElement` true, `LSMinimumSystemVersion` 13.0, copyright "MIT License, Michael Lip", `CFBundleIconFile` AppIcon. Also added `CFBundlePackageType APPL`, `CFBundleInfoDictionaryVersion`, `CFBundleDevelopmentRegion`, `CFBundleDisplayName`, `NSHighResolutionCapable`, `NSPrincipalClass NSApplication`, `LSApplicationCategoryType developer-tools`. |
| `scripts/make_icon.py` | Pillow renderer. 1024 master: Big Sur grid (824 px tile, 100 px margin, radius 185), #030803 tile with a faint green centre lift, mirrored katakana + digit rain (bright head, fading tail), 270 degree gauge arc 70 percent filled with ticks, bold neon "+", bloom, thin rim, drop shadow. 16 and 32 px use a separate simplified drawing (plus + arc, no rain) because rain is noise at that size. Deterministic (seed 41). Falls back to procedural strokes if no katakana font is found. |
| `Resources/AppIcon.iconset/*.png` | 12 committed PNGs: 16, 32, 64, 128, 256, 512 at 1x and 2x (incl. the requested 64 names). Rendered here with `unifont_jp.otf` (a pixel font, which suits the Matrix look). Re-running on a Mac picks Hiragino first, so the rain glyphs will look different if you regenerate there. |
| `scripts/build-app.sh` | Builds `Headroom` and `headroom` products one at a time (see the collision issue below), stages each binary immediately, assembles `build/Headroom.app` (MacOS/Headroom, Info.plist, PkgInfo `APPL????`, Resources/AppIcon.icns, any SwiftPM `*.bundle`), copies the CLI to `build/headroom` **and** to `Contents/Helpers/headroom`, ad-hoc signs (`codesign --force -s -` on the CLI, `--force --deep -s -` on the app), verifies with `codesign --verify --deep --strict`, prints sizes and `lipo -archs`. `UNIVERSAL=1` tries `--arch arm64 --arch x86_64` and falls back to native with a warning. `CLI_PRODUCT=...` overrides the CLI product name. Dies with a clear message if the two staged binaries are byte-identical. |
| `scripts/test-core-linux.sh` | Copies `Sources/HeadroomCore` and `Tests/HeadroomCoreTests` into a throwaway package (`.build/core-only`) with a generated manifest that has nothing else, then `swift build --target HeadroomCore` and `swift test`. Needed because `swift test` on the real package builds every target, and the app/CLI/probes need AppKit/Darwin. |
| `Makefile` | `build`, `app`, `test`, `run`, `demo`, `install`, `uninstall`, `zip`, `icon`, `lint`, `clean`. Version is read from Info.plist via PlistBuddy (falls back to 0.1.0). `zip` also writes `dist/<zip>.sha256`. |
| `install.sh` | curl-pipe-bash safe: only assignments and functions until `main "$@"` on the last line (verified: a truncated download is a syntax error and runs nothing). Checks Darwin, macOS >= 13, `xcode-select -p` (runs `xcode-select --install` and explains when missing), git/make/swift present, Swift >= 5.9 (Package.swift is tools 5.9), Xcode license not yet accepted. Shallow clone or update (`fetch --depth 1` + `reset --hard FETCH_HEAD` + `clean -fdx -e .build` so the build cache survives) into `~/.headroom/src`, quits a running Headroom (`pkill -x Headroom`), `make install NO_OPEN=1 PATH_HINT=0`, opens the app, prints next steps (Cmd-drag, `headroom --line` for tmux and Claude Code `statusLine`, PATH hint). Env: `HEADROOM_PREFIX`, `HEADROOM_HOME`, `HEADROOM_REF`, `HEADROOM_REPO`, `NO_OPEN`, `NO_COLOR`. Green ANSI only when stdout is a tty. |
| `uninstall.sh` | Same safe structure. Quits the app (AppleScript quit by bundle id, then `pkill -x`), removes `~/Applications/Headroom.app` and `/Applications/Headroom.app` **only if** their bundle id matches, removes `headroom` from `$HEADROOM_PREFIX/bin`, `~/.local/bin`, `/usr/local/bin` **only if** it looks like ours (symlink into the app or contains "Headroom"), removes `~/.headroom`, `defaults delete` the bundle id, the prefs plist, `~/Library/Caches/<id>`, `~/Library/Application Support/Headroom`, then prints the Login Items hint. |
| `.github/workflows/ci.yml` | `macos` job on macos-14: `scripts/build-app.sh`, `swift build -c release`, `swift test`, bundle checks (plutil, executables present, codesign verify, lipo, `headroom --line` as a non-fatal smoke run), `make zip`, upload zip + sha256 + CLI. `linux-core` job in the official `swift:5.10-jammy` container running `scripts/test-core-linux.sh`. `scripts` job: `bash -n`, shellcheck, `py_compile`. |
| `.github/workflows/release.yml` | On `v*` tags (or manual dispatch with a tag): fails if the tag is not `v` + Info.plist version, `swift test`, `make zip`, codesign verify, writes release notes (install.sh path avoids Gatekeeper; downloaded zip is ad-hoc signed and needs right-click Open on 13/14, Open Anyway in Privacy & Security on 15+, or `xattr -dr com.apple.quarantine`; how to link the bundled CLI; the zip's SHA-256), then `gh release create` (or `upload --clobber` + `edit` if the release already exists) with `GITHUB_TOKEN`. |

## How it was tested (here, on Linux)

- `bash -n` and shellcheck 0.11.0 clean on install.sh, uninstall.sh, scripts/*.sh (`make lint`).
- actionlint clean on both workflows. The release notes heredoc was extracted from the YAML and run to check
  the rendered Markdown.
- `scripts/test-core-linux.sh` run for real with Swift 5.10.1 on Ubuntu 24.04 against the current
  placeholder core: builds and passes the 1 placeholder test. `swift build --target HeadroomCore` on the real
  package also works on Linux.
- `scripts/build-app.sh` run with stub `uname`/`swift`/`codesign`/`iconutil`: native path, universal-fails-
  then-falls-back path, and the identical-binaries guard all behave. The bundle layout it produced was checked.
- `install.sh` run end to end with stubs and a fake HOME, cloning this repo from a `file://` URL: fresh
  install, update of an existing checkout, macOS 12 refusal, missing CLT, Swift 5.8 refusal, truncated
  download. `uninstall.sh` against the result: removes ours, leaves a foreign `headroom` in place.
- Icon PNGs inspected visually at 1024 and 64.
- No emojis or em-dashes in any owned file (scripted scan).

## Assumptions

1. The app session's executable accepts `--demo` (Makefile `demo` target) and the CLI accepts `--line`
   and `--json` (install.sh next steps, CI smoke run). CI does not fail if `--line` exits non-zero.
2. The app sets nothing that conflicts with `LSUIElement` true (it may still call
   `setActivationPolicy(.accessory)`, which is harmless).
3. The app does not declare SwiftPM resources. If it does, build-app.sh copies `*.bundle` into
   `Contents/Resources`, but SwiftPM's generated `Bundle.module` accessor for executables looks next to the
   **.app** (`Bundle.main.bundleURL`), not in `Contents/Resources`, and would crash. Prefer loading assets
   with `Bundle.main` or embedding them in code.
4. "Start at login" (if the app session builds it) uses `SMAppService.mainApp`, which needs the app in a
   stable location; `~/Applications/Headroom.app` is that location. uninstall.sh can only hint at removing
   the Login Items entry; it does not touch BTM.
5. `HEADROOM_PREFIX` means "CLI goes to `$HEADROOM_PREFIX/bin`". The app always goes to `~/Applications`
   (override with `APPDIR=` on `make install`). Without a prefix the CLI goes to `~/.local/bin` if it
   exists, else `/usr/local/bin` if writable, else `~/.local/bin` (created). That is exactly the brief's rule.
6. `make uninstall` is a lighter version (app + CLI); `uninstall.sh` is the full one (prefs, ~/.headroom).
7. The CLI is also shipped inside the app at `Contents/Helpers/headroom` so the release zip carries it.
   This was not in the brief; I added it because otherwise zip users get no CLI. The app session could
   offer an "Install command line tool" menu item that symlinks it.
8. Release tags must equal `v` + `CFBundleShortVersionString`. Bump Info.plist before tagging.
9. Branch: both `cloud/ship` and the session's assigned branch were pushed; nothing else.

## Known issue that needs a Package.swift change (I may not edit it)

**Product names `Headroom` and `headroom` differ only by case.** SwiftPM writes both executables into the
same `.build/<config>/` directory, and the default macOS volume (APFS, case-insensitive) treats
`Headroom` and `headroom` as the **same file**. Consequences I expect (could not reproduce: this container
cannot mount a case-insensitive filesystem):

- Whichever product links last overwrites the other's binary.
- When both are linked in one build (`swift build`, `swift test`), their `*.product/Objects.LinkFileList`
  paths also collide, so a parallel build can link the wrong objects (wrong binary, or duplicate `main`
  link errors). This can make the CI `swift build -c release` / `swift test` steps fail or flake.

Mitigation in build-app.sh: build each product separately with `--product`, copy it out before building the
next, and refuse to continue if the two copies are identical. That should keep `make app` / install correct
even with the current manifest.

**Recommended fix (for whoever owns Package.swift):** rename the CLI product, for example
`.executable(name: "headroom-cli", targets: ["headroom-cli"])`, then build with
`CLI_PRODUCT=headroom-cli scripts/build-app.sh` (or change the default `CLI_PRODUCT` in build-app.sh to
`headroom-cli`). The installed command name stays `headroom` because build-app.sh copies it to
`build/headroom`. If the CI `swift build` / `swift test` steps flake on macOS before that rename lands, this
is the reason.

## Must verify on a real Mac

1. `make app` produces a launchable `build/Headroom.app`: menu bar item appears, no Dock icon, icon shows in
   Finder / Get Info. `lipo -archs` shows the expected arch.
2. `cmp build/Headroom.app/Contents/MacOS/Headroom build/headroom` reports that they differ, i.e. the app
   and CLI are really different binaries (the case collision above).
3. `iconutil -c icns` accepts the staged iconset (only the 10 standard names are passed; the two
   `icon_64x64*` files are skipped on purpose because iconutil is not documented to accept them).
4. `codesign --verify --deep --strict build/Headroom.app` passes with the CLI in `Contents/Helpers`.
   `codesign --deep` is deprecated for signing by Apple but works for ad-hoc; if it complains, sign
   `Contents/Helpers/headroom` first, then the app without `--deep`.
5. `make install` then launching from `~/Applications` works; re-running `make install` while the app runs
   replaces it cleanly (pkill + rm + ditto). Replacing the CLI with rm then cp avoids the "killed: 9"
   cached-signature problem; confirm.
6. `UNIVERSAL=1 make app` with full Xcode gives `x86_64 arm64`; with only CLT it should warn and fall back.
7. `curl -fsSL .../install.sh | bash` on a clean user account, including the no-CLT path (dialog opens,
   script exits with instructions) and a second run (update path).
8. `uninstall.sh` removes everything and leaves an unrelated `/usr/local/bin/headroom` alone.
9. The first real CI run: the `swift:5.10-jammy` container job (checkout inside a container, bash present)
   and the macOS job. If the core session adds Foundation-only APIs that differ on Linux
   (e.g. `JSONEncoder.OutputFormatting.sortedKeys` is fine, `ProcessInfo` bits may not be), the Linux job
   will tell.
10. Release workflow on a test tag (for example push `v0.1.0` on a fork): release is created with zip +
    sha256, notes render, and a downloaded zip opens after `xattr -dr com.apple.quarantine`.
11. Bash 3.2 (macOS /bin/bash): scripts avoid bash 4 features (no associative arrays, no `mapfile`,
    empty-array expansion guarded), but they were only run under bash 5 here.

## Known gaps

- No notarization or Developer ID signing (no paid account, by design). Downloaded zips will always hit
  Gatekeeper; install.sh is the smooth path.
- `swift test` with only the Command Line Tools (no Xcode) historically lacks XCTest on some versions; the
  installer never runs tests, but `make test` may fail on a CLT-only Mac.
- The installer needs about 1 to 2 minutes and a few hundred MB for the first build, and leaves the build
  cache in `~/.headroom/src/.build` to speed up updates (uninstall removes it).
- The icon was rendered with a Linux pixel font; regenerating on a Mac changes the glyphs. The 16/32 px
  variants have no rain and a slightly smaller margin than the larger sizes.
- No Homebrew tap / cask.
- CI uploads the zip, not a bare `.app` (actions/upload-artifact drops permissions and symlinks).
