#!/usr/bin/env python3
"""Render the Headroom app icon into Resources/AppIcon.iconset.

Look: rounded-square near-black tile (#030803), neon green (#00FF41) katakana
and digit rain, a bold "+" in the middle and a gauge arc around it.

Usage:
    pip install pillow
    python3 scripts/make_icon.py            # writes Resources/AppIcon.iconset/*.png
    python3 scripts/make_icon.py --out DIR  # writes somewhere else

Output is deterministic for a given font (seeded RNG). The katakana font is
picked from a list of common macOS / Linux fonts; if none has katakana the
script falls back to procedurally drawn glyph strokes, so it always works.
"""

import argparse
import math
import os
import random
import sys

try:
    from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont
except ImportError:
    sys.stderr.write("make_icon.py needs Pillow: pip install pillow\n")
    sys.exit(1)

NEON = (0x00, 0xFF, 0x41)
TILE = (0x03, 0x08, 0x03)
MASTER = 1024

# (file name, pixel size) as iconutil expects them.
SIZES = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_64x64.png", 64),
    ("icon_64x64@2x.png", 128),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

KATAKANA = "アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン"
DIGITS = "0123456789"

FONT_CANDIDATES = [
    "/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc",
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
    "/System/Library/Fonts/AppleSDGothicNeo.ttc",
    "/Library/Fonts/Arial Unicode.ttf",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf",
    "/usr/share/fonts/opentype/unifont/unifont_jp.otf",
    "/usr/share/fonts/truetype/unifont/unifont_jp.ttf",
]


def font_has_katakana(font):
    """True when the font renders katakana differently from a missing glyph."""
    def ink(ch):
        im = Image.new("L", (64, 64), 0)
        ImageDraw.Draw(im).text((4, 4), ch, font=font, fill=255)
        return im.tobytes()
    try:
        missing = ink("￿")
        return ink("ア") != missing and ink("ネ") != missing and any(ink("ア"))
    except Exception:
        return False


def load_font(size):
    for path in FONT_CANDIDATES:
        if not os.path.exists(path):
            continue
        try:
            f = ImageFont.truetype(path, size)
        except Exception:
            continue
        if font_has_katakana(f):
            return f, path
    return None, None


def procedural_glyph(draw, x, y, cell, rng, fill):
    """Fallback glyph: 2-4 katakana-like strokes inside a cell."""
    w = max(1, cell // 9)
    for _ in range(rng.randint(2, 4)):
        x0 = x + rng.uniform(0.15, 0.85) * cell
        y0 = y + rng.uniform(0.1, 0.9) * cell
        ang = rng.choice([0, 90, 45, 135, 70, 110])
        ln = rng.uniform(0.3, 0.7) * cell
        x1 = x0 + math.cos(math.radians(ang)) * ln
        y1 = y0 + math.sin(math.radians(ang)) * ln
        draw.line([(x0, y0), (x1, y1)], fill=fill, width=w)


def rounded_mask(size, inset, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([inset, inset, size - inset - 1, size - inset - 1],
                                        radius=radius, fill=255)
    return m


def neon(alpha):
    return NEON + (int(max(0, min(255, alpha))),)


def render_rain(size, rng, font):
    """Columns of falling glyphs: bright head, fading tail. Returns RGBA layer."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cell = size // 16
    cols = size // cell
    rows = size // cell
    stroke = max(1, cell // 24)
    for c in range(cols):
        if rng.random() < 0.1:
            continue
        x = c * cell + (size - cols * cell) // 2
        # One or two falling trails per column.
        for _trail in range(rng.choice([1, 1, 2])):
            length = rng.randint(5, 13)
            head = rng.randint(3, rows)
            draw_trail(layer, rng, font, x, head, length, cell, stroke)
    return layer


def draw_trail(layer, rng, font, x, head, length, cell, stroke):
    """One falling trail: bright head at `head`, fading tail above it."""
    for i in range(length):
        row = head - i
        if row < 0:
            break
        y = row * cell
        fade = 1.0 - i / length
        alpha = 240 if i == 0 else 40 + 150 * fade * fade
        ch = rng.choice(KATAKANA + DIGITS) if rng.random() < 0.85 else rng.choice(DIGITS)
        glyph = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glyph)
        colour = (170, 255, 190, int(alpha)) if i == 0 else neon(alpha)
        if font is not None:
            gd.text((cell / 2, cell / 2), ch, font=font, fill=colour, anchor="mm",
                    stroke_width=stroke, stroke_fill=colour)
            if ch not in DIGITS:
                glyph = glyph.transpose(Image.FLIP_LEFT_RIGHT)  # mirrored, like the film
        else:
            procedural_glyph(gd, 0, 0, cell, rng, colour)
        layer.alpha_composite(glyph, (x, y))


def render_master(font):
    """Full detail 1024 px icon."""
    size = MASTER
    rng = random.Random(41)
    inset = 100                 # Big Sur icon grid: 824 px tile on a 1024 canvas
    radius = 185
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # Tile with a faint radial green lift in the middle.
    tile = Image.new("RGBA", (size, size), TILE + (255,))
    glow = Image.new("L", (size, size), 0)
    ImageDraw.Draw(glow).ellipse([size * 0.2, size * 0.2, size * 0.8, size * 0.8], fill=40)
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.12))
    tile = Image.composite(Image.new("RGBA", (size, size), (0, 60, 18, 255)), tile, glow)

    rain = render_rain(size, rng, font)
    rain_alpha = rain.getchannel("A").point(lambda a: int(a * 0.8))
    rain.putalpha(rain_alpha)
    tile.alpha_composite(rain)

    # Dark vignette behind the centre so the plus and gauge read cleanly.
    shade = Image.new("L", (size, size), 0)
    ImageDraw.Draw(shade).ellipse([size * 0.25, size * 0.25, size * 0.75, size * 0.75], fill=210)
    shade = shade.filter(ImageFilter.GaussianBlur(size * 0.05))
    tile = Image.composite(Image.new("RGBA", (size, size), TILE + (255,)), tile, shade)

    fg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(fg)
    cx = cy = size / 2

    # Gauge: 270 degree track, 70 percent filled, gap at the bottom.
    r = size * 0.27
    w = int(size * 0.035)
    box = [cx - r, cy - r, cx + r, cy + r]
    start, sweep = 135, 270
    d.arc(box, start, start + sweep, fill=neon(70), width=w)
    d.arc(box, start, start + sweep * 0.70, fill=neon(255), width=w)
    # Ticks just outside the track.
    for k in range(11):
        a = math.radians(start + sweep * k / 10)
        r0, r1 = r + w * 0.9, r + w * (1.9 if k % 5 == 0 else 1.5)
        d.line([(cx + math.cos(a) * r0, cy + math.sin(a) * r0),
                (cx + math.cos(a) * r1, cy + math.sin(a) * r1)],
               fill=neon(200 if k <= 7 else 80), width=max(2, w // 3))

    # Bold plus.
    arm = size * 0.15
    bar = size * 0.062
    d.rounded_rectangle([cx - arm, cy - bar / 2, cx + arm, cy + bar / 2], radius=bar * 0.25, fill=neon(255))
    d.rounded_rectangle([cx - bar / 2, cy - arm, cx + bar / 2, cy + arm], radius=bar * 0.25, fill=neon(255))

    # Neon glow under the foreground.
    bloom = fg.filter(ImageFilter.GaussianBlur(size * 0.018))
    tile.alpha_composite(bloom)
    tile.alpha_composite(bloom)
    tile.alpha_composite(fg)

    # Thin bright rim.
    rim = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle([inset + 2, inset + 2, size - inset - 3, size - inset - 3],
                                          radius=radius - 2, outline=neon(60), width=4)
    tile.alpha_composite(rim)

    # Drop shadow under the tile, then clip the tile.
    mask = rounded_mask(size, inset, radius)
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow.putalpha(rounded_mask(size, inset, radius).point(lambda a: a * 90 // 255))
    shadow = ImageChops.offset(shadow, 0, 12).filter(ImageFilter.GaussianBlur(14))
    img.alpha_composite(shadow)
    tile.putalpha(ImageChops.multiply(tile.getchannel("A"), mask))
    img.alpha_composite(tile)
    return img


def render_small(px):
    """16 and 32 px: rain is noise at this size, so draw a bold plus and gauge only."""
    s = 256  # draw big, downsample
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    inset = int(s * 0.06)
    d.rounded_rectangle([inset, inset, s - inset - 1, s - inset - 1], radius=int(s * 0.22), fill=TILE + (255,))
    c = s / 2
    r = s * 0.33
    w = int(s * 0.08)
    d.arc([c - r, c - r, c + r, c + r], 135, 405, fill=neon(90), width=w)
    d.arc([c - r, c - r, c + r, c + r], 135, 135 + 270 * 0.7, fill=neon(255), width=w)
    arm, bar = s * 0.19, s * 0.11
    d.rectangle([c - arm, c - bar / 2, c + arm, c + bar / 2], fill=neon(255))
    d.rectangle([c - bar / 2, c - arm, c + bar / 2, c + arm], fill=neon(255))
    return img.resize((px, px), Image.LANCZOS)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    default_out = os.path.join(os.path.dirname(here), "Resources", "AppIcon.iconset")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=default_out, help="iconset directory (default: %(default)s)")
    args = ap.parse_args()

    font, path = load_font(MASTER // 16 - 6)
    if font is None:
        print("make_icon: no katakana font found, using procedural glyphs")
    else:
        print("make_icon: katakana font %s" % path)

    os.makedirs(args.out, exist_ok=True)
    master = render_master(font)
    for name, px in SIZES:
        im = render_small(px) if px <= 32 else master.resize((px, px), Image.LANCZOS)
        dest = os.path.join(args.out, name)
        im.save(dest, "PNG", optimize=True)
        print("  %-24s %4d px" % (name, px))
    print("make_icon: wrote %d files to %s" % (len(SIZES), args.out))


if __name__ == "__main__":
    main()
