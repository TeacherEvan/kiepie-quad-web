#!/usr/bin/env python3
"""Generate assets/decal_lea_brand.png — ornate calligraphic "Lea" brand mark
for Lea Unicorn's right butt cheek.

Outputs a 512x512 RGBA PNG (4x supersampled LANCZOS downsample, crisp alpha-clip
threshold, transparent (0,0) corner for hidden back/rim UVs).
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_PATH = os.path.join(REPO_ROOT, "assets", "decal_lea_brand.png")

W, H = 512, 512
SS = 4
SW, SH = W * SS, H * SS

FONT_CANDIDATES = [
    "/usr/share/fonts/opentype/urw-base35/Z003-MediumItalic.otf",
    "/home/leandi-duplessis/.local/share/fonts/CormorantGaramond-Italic.ttf",
    "/usr/share/fonts/truetype/freefont/FreeSerifBoldItalic.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSerif-BoldItalic.ttf",
]


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def _draw_sparkle(draw: ImageDraw.ImageDraw, cx: float, cy: float, r: float, fill: tuple[int, int, int, int]) -> None:
    ir = r * 0.24
    pts = [
        (cx, cy - r), (cx + ir, cy - ir),
        (cx + r, cy), (cx + ir, cy + ir),
        (cx, cy + r), (cx - ir, cy + ir),
        (cx - r, cy), (cx - ir, cy - ir),
    ]
    draw.polygon(pts, fill=fill)


def main() -> None:
    img = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    text = "Lea"
    font = load_font(620)
    stroke_w = 34

    tmp = ImageDraw.Draw(img)
    bbox = tmp.textbbox((0, 0), text, font=font, stroke_width=stroke_w)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = (SW - tw) // 2 - bbox[0]
    ty = int(SH * 0.46 - th / 2) - bbox[1]

    # Deep royal-plum outer branded outline (high contrast on pearlescent coat)
    outline = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    odraw = ImageDraw.Draw(outline)
    odraw.text((tx, ty), text, font=font, fill=(64, 20, 62, 255),
               stroke_width=stroke_w, stroke_fill=(64, 20, 62, 255))
    img = Image.alpha_composite(img, outline)

    # Shimmering sunlit-gold -> rose-pink -> warm-gold gradient inside glyphs
    grad = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    gpx = grad.load()
    y0 = max(0, ty + bbox[1])
    y1 = min(SH - 1, ty + bbox[3])
    span = max(1, y1 - y0)
    for y in range(y0, y1 + 1):
        t = (y - y0) / span
        if t < 0.5:
            k = t / 0.5
            r = int(255 - 8 * k)
            g = int(228 - 92 * k)
            b = int(112 + 78 * k)
        else:
            k = (t - 0.5) / 0.5
            r = int(247 - 12 * k)
            g = int(136 + 38 * k)
            b = int(190 - 118 * k)
        for x in range(SW):
            gpx[x, y] = (r, g, b, 255)

    mask = Image.new("L", (SW, SH), 0)
    mdraw = ImageDraw.Draw(mask)
    mdraw.text((tx, ty), text, font=font, fill=255)

    fill_layer = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    fill_layer.paste(grad, (0, 0), mask)
    img = Image.alpha_composite(img, fill_layer)

    # Curved calligraphic swoosh + 3 sparkle stars
    decor = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    ddraw = ImageDraw.Draw(decor)
    sy = ty + bbox[3] + 55
    swoosh_pts = [
        (SW * 0.22, sy + 18),
        (SW * 0.38, sy + 42),
        (SW * 0.56, sy + 30),
        (SW * 0.78, sy - 14),
        (SW * 0.60, sy + 10),
        (SW * 0.39, sy + 18),
    ]
    ddraw.polygon(swoosh_pts, fill=(64, 20, 62, 255))
    ddraw.line(swoosh_pts[:4], fill=(255, 212, 92, 255), width=26, joint="curve")
    _draw_sparkle(ddraw, SW * 0.19, SH * 0.26, 46, (64, 20, 62, 255))
    _draw_sparkle(ddraw, SW * 0.19, SH * 0.26, 30, (255, 226, 118, 255))
    _draw_sparkle(ddraw, SW * 0.83, SH * 0.29, 40, (64, 20, 62, 255))
    _draw_sparkle(ddraw, SW * 0.83, SH * 0.29, 24, (248, 138, 198, 255))
    _draw_sparkle(ddraw, SW * 0.79, SH * 0.72, 34, (64, 20, 62, 255))
    _draw_sparkle(ddraw, SW * 0.79, SH * 0.72, 20, (255, 216, 108, 255))
    img = Image.alpha_composite(img, decor)

    # Downsample and threshold alpha cleanly for glTF CLIP/MASK rendering
    out = img.resize((W, H), Image.Resampling.LANCZOS)
    opx = out.load()
    for y in range(H):
        for x in range(W):
            r, g, b, a = opx[x, y]
            opx[x, y] = (r, g, b, 255) if a >= 110 else (0, 0, 0, 0)
    opx[0, 0] = (0, 0, 0, 0)

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    out.save(OUT_PATH, "PNG", optimize=True)
    print(f"DECAL_SAVED {OUT_PATH} ({W}x{H}, {os.path.getsize(OUT_PATH)} bytes)")


if __name__ == "__main__":
    main()
