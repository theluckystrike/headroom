#!/usr/bin/env python3
"""Render docs/og.png (1200x630), the social preview card for the Headroom site.

Requires Pillow (pip install pillow). Deterministic: fixed random seed.
Fonts: DejaVu Sans Mono for text; a Japanese-capable font (IPAGothic, Noto CJK,
or Hiragino on macOS) for the katakana rain if one is installed, digits otherwise.
Run from anywhere: python3 docs/make_og.py
"""
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1200, 630
GREEN = (0, 255, 65)
BG = (3, 6, 4)
KANA = "アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン"
DIGITS = "0123456789"

MONO_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
    "/Library/Fonts/DejaVuSansMono-Bold.ttf",
    "/System/Library/Fonts/Menlo.ttc",
]
MONO_REG_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    "/Library/Fonts/DejaVuSansMono.ttf",
    "/System/Library/Fonts/Menlo.ttc",
]
KANA_CANDIDATES = [
    "/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf",
    "/usr/share/fonts/truetype/fonts-japanese-gothic.ttf",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc",
]


def first_font(paths, size):
    for p in paths:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default(size)


def kana_font(size):
    for p in KANA_CANDIDATES:
        if os.path.exists(p):
            return ImageFont.truetype(p, size), KANA + DIGITS
    return first_font(MONO_REG_CANDIDATES, size), DIGITS


def main():
    rnd = random.Random(41)
    img = Image.new("RGB", (W, H), BG)

    # Rain layer, drawn on its own image so it can be blurred slightly for depth.
    rain = Image.new("RGB", (W, H), (0, 0, 0))
    rd = ImageDraw.Draw(rain)
    rfont, glyphs = kana_font(22)
    step = 26
    for x in range(6, W, step):
        if rnd.random() < 0.22:
            continue
        length = rnd.randint(6, 20)
        head = rnd.randint(40, H + 200)
        for i in range(length):
            y = head - i * 26
            if y < -26 or y > H:
                continue
            fade = 1 - i / length
            if i == 0:
                col = (190, 255, 205)
            else:
                g = int(40 + 150 * fade)
                col = (0, g, int(g * 0.25))
            rd.text((x, y), rnd.choice(glyphs), font=rfont, fill=col)
    rain = Image.blend(rain.filter(ImageFilter.GaussianBlur(0.6)), Image.new("RGB", (W, H), (0, 0, 0)), 0.45)
    img = Image.composite(rain, img, rain.convert("L").point(lambda v: 255 if v > 4 else 0))

    # Vignette toward the center so the text reads.
    shade = Image.new("L", (W, H), 0)
    sd = ImageDraw.Draw(shade)
    sd.rounded_rectangle((110, 110, W - 110, H - 110), radius=60, fill=215)
    shade = shade.filter(ImageFilter.GaussianBlur(70))
    img = Image.composite(Image.new("RGB", (W, H), BG), img, shade)

    d = ImageDraw.Draw(img)
    title_font = first_font(MONO_CANDIDATES, 128)
    pill_font = first_font(MONO_CANDIDATES, 40)
    sub_font = first_font(MONO_REG_CANDIDATES, 34)
    small_font = first_font(MONO_REG_CANDIDATES, 22)

    def centered(text, font, y):
        box = d.textbbox((0, 0), text, font=font)
        return (W - (box[2] - box[0])) // 2 - box[0], y

    # Title with glow.
    title = "HEADROOM"
    glow = Image.new("RGB", (W, H), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    tpos = centered(title, title_font, 108)
    gd.text(tpos, title, font=title_font, fill=GREEN)
    glow = glow.filter(ImageFilter.GaussianBlur(14))
    img = Image.blend(img, Image.composite(glow, img, glow.convert("L")), 0.55)
    d = ImageDraw.Draw(img)
    d.text(tpos, title, font=title_font, fill=GREEN)

    # The pill.
    pill = "AG 12  TTY 31  14.2G  +9"
    pb = d.textbbox((0, 0), pill, font=pill_font)
    pw, ph = pb[2] - pb[0], pb[3] - pb[1]
    padx, pady = 34, 22
    px0 = (W - pw) // 2 - padx
    py0 = 300
    px1, py1 = px0 + pw + 2 * padx, py0 + ph + 2 * pady
    d.rounded_rectangle((px0, py0, px1, py1), radius=18, fill=(5, 9, 6), outline=(0, 120, 34), width=2)
    # Faint rain inside the pill.
    inner = Image.new("RGB", (px1 - px0, py1 - py0), (5, 9, 6))
    idr = ImageDraw.Draw(inner)
    ifont, iglyphs = kana_font(16)
    for x in range(6, px1 - px0, 16):
        head = rnd.randint(10, py1 - py0 + 20)
        for i in range(3):
            g = max(0, 70 - i * 22)
            idr.text((x, head - i * 17), rnd.choice(iglyphs), font=ifont, fill=(0, g, int(g * 0.3)))
    mask = Image.new("L", inner.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((3, 3, inner.size[0] - 4, inner.size[1] - 4), radius=16, fill=255)
    img.paste(inner, (px0, py0), mask)
    d = ImageDraw.Draw(img)
    pglow = Image.new("RGB", (W, H), (0, 0, 0))
    ImageDraw.Draw(pglow).text((px0 + padx - pb[0], py0 + pady - pb[1]), pill, font=pill_font, fill=GREEN)
    pglow = pglow.filter(ImageFilter.GaussianBlur(6))
    img = Image.blend(img, Image.composite(pglow, img, pglow.convert("L")), 0.6)
    d = ImageDraw.Draw(img)
    d.text((px0 + padx - pb[0], py0 + pady - pb[1]), pill, font=pill_font, fill=GREEN)

    sub = "How many more AI agents can your Mac take?"
    d.text(centered(sub, sub_font, 438), sub, font=sub_font, fill=(214, 245, 221))
    foot = "github.com/theluckystrike/headroom"
    d.text(centered(foot, small_font, 520), foot, font=small_font, fill=(110, 170, 125))

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "og.png")
    img.save(out, optimize=True)
    print(f"wrote {out} {img.size}")


if __name__ == "__main__":
    main()
