#!/usr/bin/env python3
"""Generate assets/decal_lea_brand.png — bold, high-contrast calligraphic "Lea"
brand mark for Lea Unicorn's right butt cheek.

Outputs a 512x512 RGBA PNG (4x supersampled LANCZOS downsample, crisp alpha-clip
threshold, transparent (0,0) corner for hidden back/rim UVs).
"""
import os
from PIL import Image, ImageDraw, ImageFont

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


def _draw_sparkle(draw: ImageDraw.ImageDraw, cx: float, cy: float, r: float,
                  fill: tuple[int, int, int, int]) -> None:
    ir = r * 0.24
    pts = [
        (cx, cy - r), (cx + ir, cy - ir),
        (cx + r, cy), (cx + ir, cy + ir),
        (cx, cy + r), (cx - ir, cy + ir),
        (cx - r, cy), (cx - ir, cy - ir),
    ]
    draw.polygon(pts, fill=fill)


def _cubic_bezier(p0: tuple[float, float], p1: tuple[float, float],
                  p2: tuple[float, float], p3: tuple[float, float],
                  steps: int = 40) -> list[tuple[float, float]]:
    pts: list[tuple[float, float]] = []
    for i in range(steps + 1):
        t = i / steps
        mt = 1.0 - t
        x = (mt**3) * p0[0] + 3 * (mt**2) * t * p1[0] + 3 * mt * (t**2) * p2[0] + (t**3) * p3[0]
        y = (mt**3) * p0[1] + 3 * (mt**2) * t * p1[1] + 3 * mt * (t**2) * p2[1] + (t**3) * p3[1]
        pts.append((x, y))
    return pts


def _draw_tapered_ribbon(draw: ImageDraw.ImageDraw, pts: list[tuple[float, float]],
                         w_start: float, w_mid: float, w_end: float,
                         fill: tuple[int, int, int, int]) -> None:
    n = len(pts)
    for i, (x, y) in enumerate(pts):
        t = i / max(1, n - 1)
        r = (w_start * (1.0 - 2 * t) + w_mid * (2 * t)) if t < 0.5 else (
            w_mid * (2.0 - 2 * t) + w_end * (2 * t - 1.0))
        r = max(2.0, r)
        draw.ellipse((x - r, y - r, x + r, y + r), fill=fill)


def main() -> None:
    img = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    text = "Lea"
    font = load_font(920)
    stroke_w = 68

    tmp = ImageDraw.Draw(img)
    bbox = tmp.textbbox((0, 0), text, font=font, stroke_width=stroke_w)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = (SW - tw) // 2 - bbox[0]
    ty = int(SH * 0.42 - th / 2) - bbox[1]

    # Thick deep royal-plum outer branded outline for crisp legibility on pearl coat
    outline = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    odraw = ImageDraw.Draw(outline)
    odraw.text((tx, ty), text, font=font, fill=(32, 4, 48, 255),
               stroke_width=stroke_w, stroke_fill=(32, 4, 48, 255))
    img = Image.alpha_composite(img, outline)

    # Gleaming sunlit-gold top bevel -> hot-rose-magenta -> royal-violet gradient
    grad = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    gpx = grad.load()
    y0 = max(0, ty + bbox[1])
    y1 = min(SH - 1, ty + bbox[3])
    span = max(1, y1 - y0)
    for y in range(y0, y1 + 1):
        t = (y - y0) / span
        if t < 0.24:
            k = t / 0.24
            r = 255
            g = int(244 - 72 * k)
            b = int(146 - 10 * k)
        elif t < 0.56:
            k = (t - 0.24) / 0.32
            r = 255
            g = int(172 - 120 * k)
            b = int(136 + 52 * k)
        else:
            k = (t - 0.56) / 0.44
            r = int(255 - 118 * k)
            g = int(52 - 18 * k)
            b = int(188 + 67 * k)
        for x in range(SW):
            gpx[x, y] = (r, g, b, 255)

    mask = Image.new("L", (SW, SH), 0)
    mdraw = ImageDraw.Draw(mask)
    mdraw.text((tx, ty), text, font=font, fill=255)

    fill_layer = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    fill_layer.paste(grad, (0, 0), mask)
    img = Image.alpha_composite(img, fill_layer)

    # Smooth tapered golden calligraphic flourish + 4-point sparkle stars
    decor = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    ddraw = ImageDraw.Draw(decor)
    sy = min(SH - 210, ty + bbox[3] + 58)
    swoosh_pts = _cubic_bezier(
        (SW * 0.11, sy + 20),
        (SW * 0.36, sy + 72),
        (SW * 0.66, sy + 24),
        (SW * 0.90, sy - 34),
        steps=220,
    )
    _draw_tapered_ribbon(ddraw, swoosh_pts, 24, 42, 20, (36, 6, 52, 255))
    _draw_tapered_ribbon(ddraw, swoosh_pts, 10, 23, 8, (255, 222, 88, 255))

    for sx, s_y, sr_out, sr_in, col in (
        (SW * 0.14, SH * 0.21, 82, 48, (255, 226, 98, 255)),
        (SW * 0.87, SH * 0.22, 74, 44, (255, 84, 182, 255)),
        (SW * 0.82, SH * 0.80, 62, 36, (108, 224, 255, 255)),
    ):
        _draw_sparkle(ddraw, sx, s_y, sr_out, (36, 6, 52, 255))
        _draw_sparkle(ddraw, sx, s_y, sr_in, col)
    img = Image.alpha_composite(img, decor)

    # Downsample and threshold alpha cleanly for glTF CLIP/MASK rendering
    out = img.resize((W, H), Image.Resampling.LANCZOS)
    opx = out.load()
    for y in range(H):
        for x in range(W):
            r, g, b, a = opx[x, y]
            opx[x, y] = (r, g, b, 255) if a >= 115 else (0, 0, 0, 0)
    opx[0, 0] = (0, 0, 0, 0)

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    out.save(OUT_PATH, "PNG", optimize=True)
    print(f"DECAL_SAVED {OUT_PATH} ({W}x{H}, {os.path.getsize(OUT_PATH)} bytes)")


if __name__ == "__main__":
    main()
