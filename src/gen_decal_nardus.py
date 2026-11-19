#!/usr/bin/env python3
"""Generate assets/decal_nardus.png — bold athletic back-of-shirt print for NARDUS.

Outputs a 1024x512 RGBA PNG (right-side up; UVs on the curved shirt decal quad
map directly without any upside-down image hack).
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_PATH = os.path.join(REPO_ROOT, "assets", "decal_nardus.png")

W, H = 1024, 512
FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
]


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def main() -> None:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    text = "NARDUS"
    font = load_font(196)

    # Measure text with stroke
    stroke_w = 14
    tmp = ImageDraw.Draw(img)
    bbox = tmp.textbbox((0, 0), text, font=font, stroke_width=stroke_w)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = (W - tw) // 2 - bbox[0]
    ty = int(H * 0.44 - th / 2) - bbox[1]

    # Subtle drop shadow for depth against the jersey fabric
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow)
    sdraw.text((tx + 6, ty + 10), text, font=font, fill=(14, 10, 22, 195),
               stroke_width=stroke_w, stroke_fill=(14, 10, 22, 195))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=4))
    img = Image.alpha_composite(img, shadow)

    # Dark outline layer (crisp high-contrast edge against crimson-magenta jersey)
    outline_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    odraw = ImageDraw.Draw(outline_layer)
    odraw.text((tx, ty), text, font=font, fill=(20, 14, 30, 255),
               stroke_width=stroke_w, stroke_fill=(20, 14, 30, 255))
    img = Image.alpha_composite(img, outline_layer)

    # Warm gold athletic vertical gradient fill masked by the glyph interior
    grad = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gpx = grad.load()
    y0 = max(0, ty + bbox[1])
    y1 = min(H - 1, ty + bbox[3])
    span = max(1, y1 - y0)
    for y in range(y0, y1 + 1):
        t = (y - y0) / span
        # Bright warm gold top -> rich amber-gold bottom
        r = int(255 - 8 * t)
        g = int(232 - 58 * t)
        b = int(105 - 70 * t)
        for x in range(W):
            gpx[x, y] = (r, g, b, 255)

    mask = Image.new("L", (W, H), 0)
    mdraw = ImageDraw.Draw(mask)
    mdraw.text((tx, ty), text, font=font, fill=255)

    fill_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    fill_layer.paste(grad, (0, 0), mask)
    img = Image.alpha_composite(img, fill_layer)

    # Sleek varsity underline bar beneath "NARDUS"
    bar_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bdraw = ImageDraw.Draw(bar_layer)
    bar_w = int(tw * 0.78)
    bx0 = (W - bar_w) // 2
    bx1 = bx0 + bar_w
    by0 = ty + bbox[3] + 24
    by1 = by0 + 24
    # Dark outline pill
    bdraw.rounded_rectangle([bx0 - 8, by0 - 8, bx1 + 8, by1 + 8], radius=16,
                            fill=(20, 14, 30, 255))
    # Gold interior pill
    bdraw.rounded_rectangle([bx0, by0, bx1, by1], radius=10,
                            fill=(255, 206, 68, 255))
    img = Image.alpha_composite(img, bar_layer)

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    img.save(OUT_PATH, "PNG", optimize=True)
    print(f"DECAL_SAVED {OUT_PATH} ({W}x{H})")


if __name__ == "__main__":
    main()
