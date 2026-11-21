#!/usr/bin/env python3
"""Generate assets/plate_bigben.png — UK-style rear license plate reading "BIG-BEN".

Outputs a 512x128 RGBA PNG (right-side up) for the Aston Martin rear fascia.
"""
import os
from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_PATH = os.path.join(REPO_ROOT, "assets", "plate_bigben.png")

W, H = 512, 128
FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/roboto/unhinted/RobotoTTF/Roboto-Black.ttf",
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
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    px = img.load()

    # Rich UK rear-plate golden-yellow vertical gradient (#F6C820 -> #E3B110)
    for y in range(H):
        t = y / max(1, H - 1)
        r = int(246 - (246 - 227) * t)
        g = int(200 - (200 - 177) * t)
        b = int(32 - (32 - 16) * t)
        for x in range(W):
            px[x, y] = (r, g, b, 255)

    draw = ImageDraw.Draw(img)

    # Outer dark metallic border + inset hairline border
    draw.rounded_rectangle([2, 2, W - 3, H - 3], radius=12, outline=(18, 20, 24, 255), width=6)
    draw.rounded_rectangle([10, 10, W - 11, H - 11], radius=8, outline=(42, 44, 48, 190), width=2)

    # Subtle corner mounting bolts
    for cx, cy in [(26, 24), (W - 26, 24), (26, H - 24), (W - 26, H - 24)]:
        draw.ellipse([cx - 5, cy - 5, cx + 5, cy + 5], fill=(32, 34, 38, 255), outline=(140, 120, 40, 255), width=1)

    # Bold centered "BIG-BEN" text
    text = "BIG-BEN"
    font = load_font(86)
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = (W - tw) // 2 - bbox[0]
    ty = (H - th) // 2 - bbox[1] - 2
    draw.text((tx, ty), text, font=font, fill=(14, 15, 18, 255))

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    img.save(OUT_PATH, "PNG", optimize=True)
    print(f"PLATE_SAVED {OUT_PATH} ({W}x{H})")


if __name__ == "__main__":
    main()
