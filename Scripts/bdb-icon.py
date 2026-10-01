#!/usr/bin/env python3
"""Regenerate Brand/AppIcon.iconset (BDB AO Codenotch icon). Needs Pillow.

Paper squircle, ink notch on the right edge, green ring with a deep-green arc.
Palette is the AOS cloud CI (oklch values converted to sRGB below).
"""
import math, os
from PIL import Image, ImageDraw

def oklch(L, C, h):
    a, b = C * math.cos(math.radians(h)), C * math.sin(math.radians(h))
    l_ = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m_ = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s_ = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    rgb = (4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_,
           -1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_,
           -0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_)
    f = lambda c: 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055
    return tuple(max(0, min(255, round(255 * f(max(0, c))))) for c in rgb)

PAPER, PAPER2 = oklch(.97, .012, 95), oklch(.93, .018, 95)
GREEN, DEEP, INK = oklch(.72, .17, 145), oklch(.40, .12, 145), oklch(.18, .025, 265)

S = 4096  # supersample, then shrink
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
m, r = int(S * .098), int(S * .22)  # macOS icon grid margin / corner
box = (m, m, S - m, S - m)
d.rounded_rectangle(box, r, fill=PAPER)
# soft lower band for depth
band = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(band).rectangle((0, int(S * .62), S, S), fill=PAPER2)
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle(box, r, fill=255)
img.paste(band, (0, 0), Image.composite(band.split()[3], Image.new("L", (S, S), 0), mask))
# the notch: ink block hugging the right edge
nx0, ny0, ny1 = int(S * .56), int(S * .36), int(S * .64)
notch = Image.new("L", (S, S), 0)
nd = ImageDraw.Draw(notch)
nd.rounded_rectangle((nx0, ny0, S - m + r, ny1), int(S * .14), fill=255)
notch = Image.composite(notch, Image.new("L", (S, S), 0), mask)
img.paste(Image.new("RGBA", (S, S), INK), (0, 0), notch)
# ring: green track with a deep-green progress arc
cx, cy, R, w = int(S * .715), int(S * .5), int(S * .075), int(S * .03)
d = ImageDraw.Draw(img)
d.ellipse((cx - R, cy - R, cx + R, cy + R), outline=GREEN, width=w)
d.arc((cx - R, cy - R, cx + R, cy + R), -90, 150, fill=PAPER, width=w)
d.arc((cx - R, cy - R, cx + R, cy + R), -90, 150, fill=GREEN, width=w)
# left: a green-deep status dot cluster hinting at agents
for i, col in enumerate((GREEN, DEEP, INK)):
    x = int(S * (.26 + i * .1)); y = int(S * .70)
    d.ellipse((x - S * .03, y - S * .03, x + S * .03, y + S * .03), fill=col)

out = os.path.join(os.path.dirname(__file__), "..", "Brand", "AppIcon.iconset")
os.makedirs(out, exist_ok=True)
for base in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px = base * scale
        name = f"icon_{base}x{base}{'@2x' if scale == 2 else ''}.png"
        img.resize((px, px), Image.LANCZOS).save(os.path.join(out, name))
print("ok")
