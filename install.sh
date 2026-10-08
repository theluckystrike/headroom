#!/usr/bin/env bash
# Headroom installer.
#
#   curl -fsSL https://raw.githubusercontent.com/theluckystrike/headroom/main/install.sh | bash
#
# On Apple silicon it downloads the latest release zip with curl, checks its
# SHA-256 and installs it. Files fetched by curl are not quarantined, so no
# Gatekeeper prompt appears. On Intel, or when the download fails, it builds
# from source with the Xcode Command Line Tools instead. Either way it installs
# Headroom.app into ~/Applications and the `headroom` CLI into ~/.local/bin
# (or /usr/local/bin), then launches the app.
#
# Environment:
#   HEADROOM_BUILD=1  always build from source, skip the release download
#   HEADROOM_PREFIX   install the CLI into $HEADROOM_PREFIX/bin
#   HEADROOM_HOME     where the source checkout lives (default ~/.headroom)
#   HEADROOM_REF      branch or tag to build (default main; setting it builds from source)
#   HEADROOM_REPO     git URL (default https://github.com/theluckystrike/headroom)
#   APPDIR            where Headroom.app goes (default ~/Applications)
#   NO_OPEN=1         do not launch the app after installing
#
# Everything lives in functions and `main` runs on the last line, so a
# partially downloaded script does nothing.

set -euo pipefail

HEADROOM_REPO="${HEADROOM_REPO:-https://github.com/theluckystrike/headroom}"
REF_GIVEN="${HEADROOM_REF:-}"
HEADROOM_REF="${HEADROOM_REF:-main}"
APPDIR="${APPDIR:-$HOME/Applications}"
INSTALLED_FROM="source"
HEADROOM_HOME="${HEADROOM_HOME:-$HOME/.headroom}"
SRC_DIR="$HEADROOM_HOME/src"
MIN_MACOS=13

setup_colors() {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
        GREEN=$'\033[32m'; BRIGHT=$'\033[1;92m'; DIM=$'\033[2;32m'; RED=$'\033[31m'; RESET=$'\033[0m'
    else
        GREEN=""; BRIGHT=""; DIM=""; RED=""; RESET=""
    fi
}

say()  { printf '%s>%s %s\n' "$GREEN" "$RESET" "$*"; }
note() { printf '%s  %s%s\n' "$DIM" "$*" "$RESET"; }
die()  { printf '%serror:%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

banner() {
    printf '%s' "$BRIGHT"
    printf '  HEADROOM  how many more agents fit before your Mac starts swapping\n'
    printf '%s\n' "$RESET"
}

check_macos() {
    [ "$(uname -s)" = "Darwin" ] || die "Headroom is a macOS app. This system is $(uname -s)."
    local version major
    version="$(sw_vers -productVersion)"
    major="${version%%.*}"
    if [ "$major" -lt "$MIN_MACOS" ]; then
        die "Headroom needs macOS $MIN_MACOS or newer. This Mac runs macOS $version."
    fi
    say "macOS $version on $(uname -m)"
}

check_toolchain() {
    if ! xcode-select -p >/dev/null 2>&1; then
        say "The Xcode Command Line Tools are not installed. Starting the installer now."
        xcode-select --install </dev/null >/dev/null 2>&1 || true
        note "A system dialog should have opened. Click Install, wait for it to finish"
        note "(a few minutes), then run this installer again."
        exit 1
    fi
    note "developer tools: $(xcode-select -p)"

    command -v git >/dev/null 2>&1 || die "git not found. Run: xcode-select --install"
    command -v make >/dev/null 2>&1 || die "make not found. Run: xcode-select --install"
    command -v swift >/dev/null 2>&1 || die "swift not found. Run: xcode-select --install"

    local swift_line swift_ver major minor
    if ! swift_line="$(swift --version 2>&1 </dev/null)"; then
        printf '%s\n' "$swift_line" >&2
        if printf '%s' "$swift_line" | grep -qi license; then
            die "Accept the Xcode license first: sudo xcodebuild -license accept"
        fi
        die "swift is installed but does not run (output above)."
    fi
    swift_ver="$(printf '%s\n' "$swift_line" | sed -n 's/.*Swift version \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -n 1)"
    if [ -n "$swift_ver" ]; then
        major="${swift_ver%%.*}"; minor="${swift_ver#*.}"
        if [ "$major" -lt 5 ] || { [ "$major" -eq 5 ] && [ "$minor" -lt 9 ]; }; then
            die "Swift $swift_ver is too old; Headroom needs Swift 5.9 (Xcode 15) or newer. Update the Command Line Tools in System Settings > General > Software Update."
        fi
        note "swift $swift_ver"
    else
        note "could not read the Swift version; continuing"
    fi
}

fetch_source() {
    mkdir -p "$HEADROOM_HOME"
    if [ -d "$SRC_DIR/.git" ]; then
        say "Updating source in $SRC_DIR ($HEADROOM_REF)"
        git -C "$SRC_DIR" remote set-url origin "$HEADROOM_REPO"
        git -C "$SRC_DIR" fetch --quiet --depth 1 origin "$HEADROOM_REF" </dev/null
        git -C "$SRC_DIR" reset --quiet --hard FETCH_HEAD
        git -C "$SRC_DIR" clean --quiet -fdx -e .build
    else
        say "Cloning $HEADROOM_REPO into $SRC_DIR"
        rm -rf "$SRC_DIR"
        git clone --quiet --depth 1 --branch "$HEADROOM_REF" "$HEADROOM_REPO" "$SRC_DIR" </dev/null
    fi
    note "commit $(git -C "$SRC_DIR" rev-parse --short HEAD)"
}

cli_bindir() {
    # Same rule as the Makefile: $HEADROOM_PREFIX/bin, else ~/.local/bin if it
    # exists, else /usr/local/bin if writable, else ~/.local/bin.
    if [ -n "${HEADROOM_PREFIX:-}" ]; then printf '%s\n' "$HEADROOM_PREFIX/bin"
    elif [ -d "$HOME/.local/bin" ]; then printf '%s\n' "$HOME/.local/bin"
    elif [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then printf '%s\n' /usr/local/bin
    else printf '%s\n' "$HOME/.local/bin"; fi
}

# Download the latest release and install it. Returns non-zero (and leaves
# nothing installed) whenever it cannot, so main falls back to a source build.
install_prebuilt() {
    if [ -n "${HEADROOM_BUILD:-}" ] || [ -n "$REF_GIVEN" ]; then
        return 1
    fi
    if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" != 1 ]; then
        note "no prebuilt app for Intel Macs, building from source"
        return 1
    fi

    local web tag version zip tmp app
    web="${HEADROOM_REPO%.git}"
    tag="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$web/releases/latest" 2>/dev/null || true)"
    tag="${tag##*/tag/}"
    case "$tag" in
        v[0-9]*) ;;
        *) note "could not find a release, building from source"; return 1 ;;
    esac
    version="${tag#v}"
    zip="Headroom-$version-macos.zip"

    tmp="$(mktemp -d "${TMPDIR:-/tmp}/headroom.XXXXXX")"
    say "Downloading Headroom $version"
    if ! curl -fsSL -o "$tmp/$zip" "$web/releases/download/$tag/$zip" \
        || ! curl -fsSL -o "$tmp/$zip.sha256" "$web/releases/download/$tag/$zip.sha256"; then
        rm -rf "$tmp"; note "download failed, building from source"; return 1
    fi
    if ! (cd "$tmp" && shasum -a 256 -c "$zip.sha256" >/dev/null 2>&1); then
        rm -rf "$tmp"; die "SHA-256 of $zip does not match $zip.sha256. Nothing was installed."
    fi
    note "sha256 ok"
    mkdir "$tmp/x"
    ditto -x -k "$tmp/$zip" "$tmp/x"
    app="$tmp/x/Headroom.app"
    if [ ! -x "$app/Contents/MacOS/Headroom" ] || [ ! -x "$app/Contents/Helpers/headroom" ]; then
        rm -rf "$tmp"; note "release zip looks incomplete, building from source"; return 1
    fi
    if ! "$app/Contents/Helpers/headroom" --line >/dev/null 2>&1 </dev/null; then
        rm -rf "$tmp"; note "release binary does not run on this Mac, building from source"; return 1
    fi

    stop_running_app
    local bindir
    bindir="$(cli_bindir)"
    mkdir -p "$APPDIR" "$bindir"
    rm -rf "$APPDIR/Headroom.app"
    ditto "$app" "$APPDIR/Headroom.app"
    xattr -dr com.apple.quarantine "$APPDIR/Headroom.app" 2>/dev/null || true
    # Remove before copying: overwriting a signed binary in place can get it killed on launch.
    rm -f "$bindir/headroom"
    cp "$app/Contents/Helpers/headroom" "$bindir/headroom"
    chmod 755 "$bindir/headroom"
    rm -rf "$tmp"
    INSTALLED_FROM="release $tag"
    note "installed $APPDIR/Headroom.app"
    note "installed $bindir/headroom"
}

stop_running_app() {
    if pgrep -x Headroom >/dev/null 2>&1; then
        say "Quitting the running Headroom"
        pkill -x Headroom 2>/dev/null || true
        sleep 1
    fi
}

build_and_install() {
    say "Building (the first build takes a minute or two)"
    if ! make -C "$SRC_DIR" install NO_OPEN=1 PATH_HINT=0 </dev/null; then
        die "Build failed. Output is above. Source is in $SRC_DIR; retry with: make -C $SRC_DIR install"
    fi
}

launch() {
    if [ -n "${NO_OPEN:-}" ]; then
        return 0
    fi
    local app="$APPDIR/Headroom.app"
    if [ -d "$app" ]; then
        open "$app" || note "Could not launch $app; open it from Finder."
    fi
}

next_steps() {
    local bindir
    if [ -n "${HEADROOM_PREFIX:-}" ]; then bindir="$HEADROOM_PREFIX/bin"
    elif [ -x "$HOME/.local/bin/headroom" ]; then bindir="$HOME/.local/bin"
    else bindir="/usr/local/bin"; fi

    printf '\n%sHeadroom is installed%s (from %s).\n\n' "$BRIGHT" "$RESET" "$INSTALLED_FROM"
    printf '%s  App:%s  %s/Headroom.app (lives in the menu bar, no Dock icon)\n' "$GREEN" "$RESET" "$APPDIR"
    printf '%s  CLI:%s  %s/headroom\n\n' "$GREEN" "$RESET" "$bindir"
    printf '%sNext steps%s\n' "$GREEN" "$RESET"
    printf '  - Hold Cmd and drag the Headroom item to move it along the menu bar.\n'
    printf '  - Click it for the per agent breakdown and settings (start at login lives there).\n'
    printf '  - One line summary for scripts: headroom --line\n'
    printf '      tmux:        set -g status-right "#(headroom --line)"\n'
    printf '      Claude Code: in ~/.claude/settings.json add\n'
    printf '                   "statusLine": { "type": "command", "command": "headroom --line" }\n'
    printf '  - Full snapshot as JSON: headroom --json\n'
    case ":$PATH:" in
        *":$bindir:"*) ;;
        *)
            printf '\n%sNote:%s %s is not on your PATH. Add it:\n' "$GREEN" "$RESET" "$bindir"
            printf "  echo 'export PATH=\"%s:\$PATH\"' >> ~/.zshrc\n" "$bindir"
            ;;
    esac
    printf '\n  Update: run this installer again.\n'
    printf '  Uninstall: curl -fsSL https://raw.githubusercontent.com/theluckystrike/headroom/main/uninstall.sh | bash\n\n'
}

main() {
    setup_colors
    banner
    check_macos
    if ! install_prebuilt; then
        check_toolchain
        fetch_source
        stop_running_app
        build_and_install
    fi
    launch
    next_steps
}

main "$@"
