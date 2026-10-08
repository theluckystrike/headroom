#!/usr/bin/env python3
"""Generate docs/hero.svg: a mock of the Headroom menu bar item and its dropdown.

Deterministic (fixed seed), standard library only.
Run from anywhere: python3 docs/make_hero.py
"""
import os
import random

W, H = 1280, 690
GREEN = "#00FF41"
KANA = "アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン0123456789"
MONO = "SF Mono, Menlo, Consolas, DejaVu Sans Mono, monospace"
SANS = "-apple-system, BlinkMacSystemFont, Helvetica Neue, Helvetica, Arial, sans-serif"

rnd = random.Random(41)
out = []
add = out.append


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


add(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" '
    f'role="img" aria-label="Headroom in the macOS menu bar: AG 12, TTY 31, 14.2G free, +9 more agents fit">')
add("<defs>")
add('<linearGradient id="wall" x1="0" y1="0" x2="0" y2="1">'
    '<stop offset="0" stop-color="#07130b"/><stop offset="1" stop-color="#020403"/></linearGradient>')
add('<linearGradient id="bar" x1="0" y1="0" x2="0" y2="1">'
    '<stop offset="0" stop-color="#2a2c2b"/><stop offset="1" stop-color="#1f2120"/></linearGradient>')
add('<filter id="glow" x="-20%" y="-50%" width="140%" height="200%">'
    '<feGaussianBlur stdDeviation="2.2" result="b"/>'
    '<feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>')
add('<filter id="shadow" x="-10%" y="-10%" width="120%" height="130%">'
    '<feDropShadow dx="0" dy="14" stdDeviation="18" flood-color="#000" flood-opacity="0.7"/></filter>')
add('<clipPath id="frame"><rect x="0" y="0" width="1280" height="690" rx="18"/></clipPath>')
PILL_X, PILL_Y, PILL_W, PILL_H = 566, 9, 262, 30
add(f'<clipPath id="pillclip"><rect x="{PILL_X}" y="{PILL_Y}" width="{PILL_W}" height="{PILL_H}" rx="7"/></clipPath>')
add("</defs>")

add('<g clip-path="url(#frame)">')
add(f'<rect width="{W}" height="{H}" fill="url(#wall)"/>')

# Wallpaper rain: faint katakana trails.
add(f'<g font-family="{MONO}" font-size="15" fill="{GREEN}">')
for x in range(10, W, 24):
    if rnd.random() < 0.35:
        continue
    length = rnd.randint(4, 14)
    head = rnd.randint(60, H + 120)
    for i in range(length):
        y = head - i * 19
        if y < 56 or y > H:
            continue
        op = 0.20 * (1 - i / length) + 0.02
        if i == 0:
            op = 0.32
        add(f'<text x="{x}" y="{y}" opacity="{op:.2f}">{rnd.choice(KANA)}</text>')
add("</g>")

# Menu bar.
add(f'<rect x="0" y="0" width="{W}" height="48" fill="url(#bar)"/>')
add(f'<rect x="0" y="47" width="{W}" height="1" fill="#000" opacity="0.6"/>')
add(f'<g font-family="{SANS}" font-size="16" fill="#e8e8e8">')
add('<text x="26" y="30" font-weight="700">Terminal</text>')
for x, word in ((118, "Shell"), (176, "Edit"), (227, "View"), (283, "Window"), (360, "Help")):
    add(f'<text x="{x}" y="30">{word}</text>')
add("</g>")

# Headroom pill: near-black, faint rain behind neon text.
add(f'<rect x="{PILL_X}" y="{PILL_Y}" width="{PILL_W}" height="{PILL_H}" rx="7" fill="#050805" '
    f'stroke="{GREEN}" stroke-opacity="0.35"/>')
add(f'<g clip-path="url(#pillclip)" font-family="{MONO}" font-size="10" fill="{GREEN}">')
for x in range(PILL_X + 3, PILL_X + PILL_W, 9):
    head = rnd.randint(PILL_Y + 4, PILL_Y + PILL_H + 14)
    for i in range(rnd.randint(2, 4)):
        y = head - i * 10
        op = 0.26 - i * 0.07
        if op > 0:
            add(f'<text x="{x}" y="{y}" opacity="{op:.2f}">{rnd.choice(KANA)}</text>')
add("</g>")
add(f'<text x="{PILL_X + 14}" y="{PILL_Y + 20}" font-family="{MONO}" font-size="15.5" font-weight="700" '
    f'fill="{GREEN}" filter="url(#glow)" xml:space="preserve" textLength="{PILL_W - 28}" '
    f'lengthAdjust="spacing">AG 12  TTY 31  14.2G  +9</text>')

# Other menu bar items.
add(f'<text x="986" y="30" font-family="{SANS}" font-size="16" fill="#e8e8e8" text-anchor="end">never give up</text>')
# Wi-Fi glyph.
add('<g transform="translate(1012 33)" fill="none" stroke="#e8e8e8" stroke-width="2.4" stroke-linecap="round">'
    '<path d="M-11,-11 A15.5,15.5 0 0 1 11,-11"/><path d="M-6.4,-6.4 A9,9 0 0 1 6.4,-6.4"/>'
    '<circle cx="0" cy="-1.5" r="1.6" fill="#e8e8e8" stroke="none"/></g>')
# Battery glyph.
add('<g transform="translate(1044 15)"><rect x="0" y="0" width="30" height="15" rx="4" fill="none" '
    'stroke="#e8e8e8" stroke-opacity="0.7" stroke-width="1.4"/><rect x="2.5" y="2.5" width="20" height="10" '
    'rx="2" fill="#e8e8e8"/><rect x="31.5" y="5" width="2.5" height="5" rx="1" fill="#e8e8e8" fill-opacity="0.7"/></g>')
add(f'<text x="1254" y="30" font-family="{SANS}" font-size="16" fill="#e8e8e8" text-anchor="end">'
    'Thu Oct 8  9:41 AM</text>')

# Dropdown panel.
DX, DY, DW = PILL_X, 56, 420
rows = []
add('<g filter="url(#shadow)">')
DH = 600
add(f'<rect x="{DX}" y="{DY}" width="{DW}" height="{DH}" rx="12" fill="#0a0f0b" fill-opacity="0.97" '
    f'stroke="{GREEN}" stroke-opacity="0.22"/>')
add("</g>")

L = DX + 22
R = DX + DW - 22
y = DY + 34
add(f'<g font-family="{MONO}">')
add(f'<text x="{L}" y="{y}" font-size="13" fill="#7fae8b" letter-spacing="2">HEADROOM</text>')
add(f'<text x="{R}" y="{y}" font-size="13" fill="#7fae8b" text-anchor="end">updated 1s ago</text>')
y += 58
add(f'<text x="{L}" y="{y}" font-size="52" font-weight="700" fill="{GREEN}" filter="url(#glow)">+9</text>')
add(f'<text x="{L + 90}" y="{y - 22}" font-size="16" fill="#d8f5df">more agents fit</text>')
add(f'<text x="{L + 90}" y="{y}" font-size="13" fill="#7fae8b">before the 3.0G reserve</text>')
y += 22


def sep():
    global y
    add(f'<rect x="{L}" y="{y}" width="{DW - 44}" height="1" fill="{GREEN}" opacity="0.18"/>')
    y += 28


def row(label, value, sub=False, bright=False):
    global y
    size = 14 if sub else 15
    lx = L + 18 if sub else L
    lcol = "#7fae8b" if sub else "#c9e8d0"
    vcol = GREEN if bright else ("#a9d8b4" if sub else "#e6ffe9")
    add(f'<text x="{lx}" y="{y}" font-size="{size}" fill="{lcol}">{esc(label)}</text>')
    add(f'<text x="{R}" y="{y}" font-size="{size}" fill="{vcol}" text-anchor="end" xml:space="preserve">{esc(value)}</text>')
    y += 24 if sub else 26


sep()
row("Agents running", "12", bright=True)
row("Claude Code", "5    6.8G", sub=True)
row("Codex", "4    2.9G", sub=True)
row("Hermes", "3    1.6G", sub=True)
y += 4
row("Per agent (median)", "1.2G")
y += 2
sep()
row("Terminal sessions", "31", bright=True)
row("iTerm2", "18", sub=True)
row("Ghostty", "9", sub=True)
row("tmux", "4", sub=True)
y += 2
sep()
row("Available", "14.2G of 36G", bright=True)
row("Swap used", "3.1G of 8.0G")
row("Pressure", "normal")
y += 2
sep()
row("Settings...", "")
row("Quit Headroom", "")
add("</g>")
add("</g>")
add("</svg>")

assert y < DY + DH, f"panel too short: content ends at {y}, panel ends at {DY + DH}"
path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hero.svg")
with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(out) + "\n")
print(f"wrote {path} (content bottom {y}, panel bottom {DY + DH})")
