# Headroom: build, test, install.
#
#   make app        build/Headroom.app + build/headroom (ad-hoc signed)
#   make install    copy to ~/Applications and ~/.local/bin, then launch
#   make zip        dist/Headroom-<version>-macos.zip (+ .sha256)
#
# Variables: HEADROOM_PREFIX=/opt/foo puts the CLI in /opt/foo/bin,
# BINDIR=... and APPDIR=... override directly, NO_OPEN=1 skips launching,
# UNIVERSAL=1 tries an arm64 + x86_64 build.

SHELL := /bin/bash

VERSION ?= $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || echo 0.1.0)

APP      := build/Headroom.app
CLI      := build/headroom
ZIP      := dist/Headroom-$(VERSION)-macos.zip
APPDIR   ?= $(HOME)/Applications
LOCALBIN := $(HOME)/.local/bin

# CLI destination: $HEADROOM_PREFIX/bin, else ~/.local/bin if it exists,
# else /usr/local/bin if writable, else ~/.local/bin (created).
ifneq ($(strip $(HEADROOM_PREFIX)),)
BINDIR ?= $(HEADROOM_PREFIX)/bin
endif
BINDIR ?= $(shell if [ -d "$(LOCALBIN)" ]; then echo "$(LOCALBIN)"; \
	elif [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then echo /usr/local/bin; \
	else echo "$(LOCALBIN)"; fi)

.PHONY: all build app test run demo install uninstall zip icon lint clean

all: app

build:
	swift build -c release

app:
	scripts/build-app.sh

test:
	swift test

run: app
	open "$(APP)"

demo: app
	"$(APP)/Contents/MacOS/Headroom" --demo

install: app
	pkill -x Headroom 2>/dev/null || true
	mkdir -p "$(APPDIR)" "$(BINDIR)"
	rm -rf "$(APPDIR)/Headroom.app"
	ditto "$(APP)" "$(APPDIR)/Headroom.app"
	# Remove before copying: overwriting a signed binary in place can get it killed on launch.
	rm -f "$(BINDIR)/headroom"
	cp "$(CLI)" "$(BINDIR)/headroom"
	chmod 755 "$(BINDIR)/headroom"
	echo "Installed $(APPDIR)/Headroom.app"
	echo "Installed $(BINDIR)/headroom"
	case ":$$PATH:" in *":$(BINDIR):"*) ;; \
	  *) echo "Note: $(BINDIR) is not on your PATH. Add it, e.g.: echo 'export PATH=\"$(BINDIR):\$$PATH\"' >> ~/.zshrc" ;; esac
	if [ -z "$(NO_OPEN)" ]; then open "$(APPDIR)/Headroom.app"; fi

uninstall:
	pkill -x Headroom 2>/dev/null || true
	rm -rf "$(APPDIR)/Headroom.app"
	for d in "$(BINDIR)" "$(LOCALBIN)" /usr/local/bin; do \
	  if [ -f "$$d/headroom" ] && [ -w "$$d" ]; then rm -f "$$d/headroom" && echo "Removed $$d/headroom"; fi; \
	done
	echo "Removed $(APPDIR)/Headroom.app"

zip: app
	mkdir -p dist
	rm -f "$(ZIP)" "$(ZIP).sha256"
	ditto -c -k --keepParent "$(APP)" "$(ZIP)"
	cd dist && shasum -a 256 "$(notdir $(ZIP))" > "$(notdir $(ZIP)).sha256"
	echo "$(ZIP)"
	cat "$(ZIP).sha256"

icon:
	python3 scripts/make_icon.py

lint:
	bash -n install.sh uninstall.sh scripts/*.sh
	shellcheck install.sh uninstall.sh scripts/*.sh

clean:
	rm -rf build dist .build
