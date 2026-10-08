#!/usr/bin/env bash
# Build Headroom.app and the headroom CLI into ./build.
#
#   scripts/build-app.sh               native arch, release
#   UNIVERSAL=1 scripts/build-app.sh   try arm64 + x86_64, fall back to native
#
# Output:
#   build/Headroom.app   menu bar app, ad-hoc signed (CLI also in Contents/Helpers)
#   build/headroom       command line tool
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/Headroom.app"
UNIVERSAL="${UNIVERSAL:-0}"

if [ -t 1 ]; then
    G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; B=$'\033[1m'; N=$'\033[0m'
else
    G=""; Y=""; R=""; B=""; N=""
fi
say()  { printf '%s==>%s %s\n' "$G" "$N" "$*"; }
warn() { printf '%swarning:%s %s\n' "$Y" "$N" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "Headroom.app can only be built on macOS (this is $(uname -s))."
command -v swift >/dev/null 2>&1 || die "swift not found. Install the Xcode Command Line Tools: xcode-select --install"

cd "$ROOT"

# --- compile ------------------------------------------------------------------
# The app product "Headroom" and the CLI product "headroom" link to the same path
# on a case-insensitive APFS volume (the macOS default), so each product is
# built and copied out to a staging dir before the other one is linked.
CLI_PRODUCT="${CLI_PRODUCT:-headroom}"
STAGE="$BUILD_DIR/.stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"

build_product() { # product dest [swift build flags...]
    local product="$1" dest="$2" bin_dir
    shift 2
    swift build -c release "$@" --product "$product" || return 1
    bin_dir="$(swift build -c release "$@" --show-bin-path)"
    [ -x "$bin_dir/$product" ] || { warn "binary not found at $bin_dir/$product"; return 1; }
    cp "$bin_dir/$product" "$dest"
    # Resource bundles SwiftPM emits next to the binaries (only if a target declares resources).
    for bundle in "$bin_dir"/*.bundle; do
        [ -e "$bundle" ] || continue
        rm -rf "$STAGE/bundles/$(basename "$bundle")"
        mkdir -p "$STAGE/bundles"
        cp -R "$bundle" "$STAGE/bundles/"
    done
}

build_all() { # [swift build flags...]
    build_product Headroom "$STAGE/Headroom" "$@" && build_product "$CLI_PRODUCT" "$STAGE/headroom" "$@"
}

BUILT=0
if [ "$UNIVERSAL" = "1" ]; then
    say "Building universal (arm64 + x86_64) release"
    if build_all --arch arm64 --arch x86_64; then
        BUILT=1
    else
        warn "Universal build failed (it needs full Xcode, not only the Command Line Tools). Falling back to native arch."
    fi
fi
if [ "$BUILT" = "0" ]; then
    say "Building release for $(uname -m)"
    build_all || die "swift build failed (see the output above)."
fi

if cmp -s "$STAGE/Headroom" "$STAGE/headroom"; then
    die "The app and CLI binaries are identical, so one product overwrote the other. Rename one product in Package.swift (see NOTES-ship.md)."
fi

# --- assemble the bundle ------------------------------------------------------
say "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$STAGE/Headroom" "$APP/Contents/MacOS/Headroom"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ -d "$STAGE/bundles" ]; then
    cp -R "$STAGE/bundles/." "$APP/Contents/Resources/"
fi

# --- icon ---------------------------------------------------------------------
ICONSET_SRC="$ROOT/Resources/AppIcon.iconset"
if ! command -v iconutil >/dev/null 2>&1; then
    warn "iconutil not found; the app will use the generic icon."
elif [ ! -d "$ICONSET_SRC" ]; then
    warn "$ICONSET_SRC missing (run: python3 scripts/make_icon.py); the app will use the generic icon."
else
    # iconutil only accepts the standard names, so stage just those.
    TMP_ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$TMP_ICONSET"
    for s in 16 32 128 256 512; do
        for suffix in "" "@2x"; do
            f="icon_${s}x${s}${suffix}.png"
            if [ -f "$ICONSET_SRC/$f" ]; then cp "$ICONSET_SRC/$f" "$TMP_ICONSET/$f"; fi
        done
    done
    if iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$TMP_ICONSET"; then
        say "Icon: Contents/Resources/AppIcon.icns"
    else
        warn "iconutil failed; the app will use the generic icon."
    fi
    rm -rf "$(dirname "$TMP_ICONSET")"
fi

# --- CLI ----------------------------------------------------------------------
# Standalone copy, plus one inside the bundle so the release zip carries it too:
#   ln -s /Applications/Headroom.app/Contents/Helpers/headroom ~/.local/bin/headroom
cp "$STAGE/headroom" "$BUILD_DIR/headroom"
mkdir -p "$APP/Contents/Helpers"
cp "$STAGE/headroom" "$APP/Contents/Helpers/headroom"
rm -rf "$STAGE"

# --- sign ---------------------------------------------------------------------
if command -v codesign >/dev/null 2>&1; then
    say "Ad-hoc signing"
    codesign --force -s - "$BUILD_DIR/headroom"
    codesign --force --deep -s - "$APP"
    codesign --verify --deep --strict "$APP" || die "codesign verification failed for $APP"
else
    warn "codesign not found; the bundle is unsigned and may not launch on Apple Silicon."
fi

# --- report -------------------------------------------------------------------
archs() { lipo -archs "$1" 2>/dev/null || file -b "$1"; }
printf '\n%sBuilt%s\n' "$B" "$N"
printf '  %-22s %s (%s)\n' "build/Headroom.app" "$(du -sh "$APP" | cut -f1)" "$(archs "$APP/Contents/MacOS/Headroom")"
printf '  %-22s %s (%s)\n' "build/headroom" "$(du -sh "$BUILD_DIR/headroom" | cut -f1)" "$(archs "$BUILD_DIR/headroom")"
printf '\n  open build/Headroom.app      run the menu bar app\n'
printf '  build/headroom --line        one line summary\n'
