#!/usr/bin/env bash
# Headroom uninstaller.
#
#   ~/.headroom/src/uninstall.sh
#   curl -fsSL https://raw.githubusercontent.com/theluckystrike/headroom/main/uninstall.sh | bash
#
# Quits the app, removes ~/Applications/Headroom.app, the `headroom` CLI,
# ~/.headroom (source checkout and build cache) and the app's preferences.
# Honors HEADROOM_PREFIX and HEADROOM_HOME like install.sh.
#
# Everything lives in functions and `main` runs on the last line, so a
# partially downloaded script does nothing.

set -euo pipefail

BUNDLE_ID="io.github.theluckystrike.headroom"
HEADROOM_HOME="${HEADROOM_HOME:-$HOME/.headroom}"

setup_colors() {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
        GREEN=$'\033[32m'; BRIGHT=$'\033[1;92m'; DIM=$'\033[2;32m'; RESET=$'\033[0m'
    else
        GREEN=""; BRIGHT=""; DIM=""; RESET=""
    fi
}

say()  { printf '%s>%s %s\n' "$GREEN" "$RESET" "$*"; }
note() { printf '%s  %s%s\n' "$DIM" "$*" "$RESET"; }

quit_app() {
    if pgrep -x Headroom >/dev/null 2>&1; then
        say "Quitting Headroom"
        osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
        sleep 1
        pkill -x Headroom 2>/dev/null || true
    fi
}

remove_path() {
    local p="$1"
    if [ -e "$p" ] || [ -L "$p" ]; then
        if rm -rf "$p" 2>/dev/null; then
            say "Removed $p"
        else
            note "Could not remove $p (permission denied). Remove it with: sudo rm -rf \"$p\""
        fi
    fi
}

# Only delete a `headroom` binary that is ours: a link into Headroom.app, or a
# file that mentions the bundle id / app name.
is_our_cli() {
    local f="$1" target
    if [ -L "$f" ]; then
        target="$(readlink "$f")"
        case "$target" in *Headroom.app*|*headroom*) return 0 ;; esac
    fi
    [ -f "$f" ] && grep -aq -e "$BUNDLE_ID" -e "HeadroomCore" -e "Headroom" "$f" 2>/dev/null
}

is_our_app() {
    local id
    id="$(defaults read "$1/Contents/Info" CFBundleIdentifier 2>/dev/null || true)"
    [ "$id" = "$BUNDLE_ID" ]
}

remove_app() {
    local app
    for app in "$HOME/Applications/Headroom.app" "/Applications/Headroom.app"; do
        [ -d "$app" ] || continue
        if is_our_app "$app"; then
            remove_path "$app"
        else
            note "Left $app alone (bundle id is not $BUNDLE_ID)"
        fi
    done
}

remove_cli() {
    local dirs=() d
    if [ -n "${HEADROOM_PREFIX:-}" ]; then dirs+=("$HEADROOM_PREFIX/bin"); fi
    dirs+=("$HOME/.local/bin" "/usr/local/bin")
    for d in "${dirs[@]}"; do
        if [ -e "$d/headroom" ] || [ -L "$d/headroom" ]; then
            if is_our_cli "$d/headroom"; then
                remove_path "$d/headroom"
            else
                note "Left $d/headroom alone (does not look like the Headroom CLI)"
            fi
        fi
    done
}

remove_data() {
    remove_path "$HEADROOM_HOME"
    if defaults read "$BUNDLE_ID" >/dev/null 2>&1; then
        defaults delete "$BUNDLE_ID" >/dev/null 2>&1 && say "Removed preferences ($BUNDLE_ID)"
    fi
    remove_path "$HOME/Library/Preferences/$BUNDLE_ID.plist"
    remove_path "$HOME/Library/Caches/$BUNDLE_ID"
    remove_path "$HOME/Library/Application Support/Headroom"
}

login_item_hint() {
    printf '\n%sHeadroom is uninstalled.%s\n' "$BRIGHT" "$RESET"
    note "If you turned on start at login, macOS may still list Headroom in"
    note "System Settings > General > Login Items. Select it there and click the minus button."
    note "(The entry does nothing now that the app is gone.)"
    printf '\n'
}

main() {
    setup_colors
    if [ "$(uname -s)" != "Darwin" ]; then
        printf 'Headroom is a macOS app; nothing to uninstall on %s.\n' "$(uname -s)"
        exit 0
    fi
    quit_app
    remove_app
    remove_cli
    remove_data
    login_item_hint
}

main "$@"
