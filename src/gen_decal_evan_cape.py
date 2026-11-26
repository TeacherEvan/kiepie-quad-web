#!/usr/bin/env python3
"""Generate assets/decal_evan_cape.png — dark tattered cloak texture with evil
gothic/heavy-metal "Ewaldt" lettering for Evan the Skeleton's torn cape.

Outputs a 512x768 RGB/RGBA PNG (4x supersampled LANCZOS downsample).
U=0..1 maps left-to-right across the back of the cape; V=1 is collar, V=0 is hem.
"""
import math
import os
import random
from PIL import Image, ImageDraw, ImageFilter

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_PATH = os.path.join(REPO_ROOT, "assets", "decal_evan_cape.png")

W, H = 512, 768
SS = 4
SW, SH = W * SS, H * SS


def _poly(pts: list[tuple[float, float]], x0: float, y0: float, sx: float, sy: float) -> list[tuple[float, float]]:
    return [(x0 + x * sx, y0 + y * sy) for x, y in pts]


def _ewaldt_polygons() -> list[list[tuple[float, float]]]:
    """Return sharp evil gothic/heavy-metal polygon strokes in normalized [0..1, 0..1] box."""
    polys: list[list[tuple[float, float]]] = []

    # --- 'E' (x: 0.00..0.185) ---
    polys.append([(0.028, 0.08), (0.068, 0.00), (0.072, 0.92), (0.032, 1.00), (0.012, 0.88), (0.022, 0.16)])
    # Top horned arm
    polys.append([(0.010, 0.12), (0.068, 0.06), (0.180, 0.03), (0.195, -0.04), (0.155, 0.17), (0.055, 0.18)])
    # Middle barbed fang
    polys.append([(0.052, 0.45), (0.145, 0.42), (0.170, 0.48), (0.130, 0.56), (0.052, 0.54)])
    # Bottom spiked arm
    polys.append([(0.012, 0.88), (0.065, 0.82), (0.165, 0.80), (0.192, 0.96), (0.140, 0.92), (0.032, 0.98)])

    # --- 'w' (x: 0.205..0.415) ---
    polys.append([(0.200, 0.28), (0.242, 0.24), (0.278, 0.84), (0.252, 0.95), (0.222, 0.42)])
    polys.append([(0.252, 0.95), (0.305, 0.36), (0.328, 0.36), (0.280, 0.88)])
    polys.append([(0.302, 0.36), (0.326, 0.36), (0.365, 0.86), (0.342, 0.96)])
    polys.append([(0.342, 0.96), (0.388, 0.30), (0.422, 0.23), (0.404, 0.42), (0.366, 0.90)])
    # Center spike
    polys.append([(0.302, 0.39), (0.314, 0.24), (0.326, 0.39)])

    # --- 'a' (x: 0.435..0.575) ---
    # Top overhanging horn-roof
    polys.append([(0.438, 0.34), (0.480, 0.25), (0.562, 0.25), (0.575, 0.35), (0.525, 0.35), (0.470, 0.38)])
    # Right spine + tail barb
    polys.append([(0.532, 0.30), (0.568, 0.28), (0.566, 0.88), (0.592, 0.96), (0.542, 0.95), (0.530, 0.84)])
    # Angular bowl
    polys.append([(0.538, 0.50), (0.455, 0.53), (0.428, 0.72), (0.452, 0.93), (0.538, 0.89),
                  (0.538, 0.79), (0.476, 0.82), (0.464, 0.71), (0.482, 0.60), (0.538, 0.59)])

    # --- 'l' (x: 0.600..0.675) ---
    polys.append([(0.602, 0.05), (0.630, -0.05), (0.652, 0.04), (0.654, 0.85), (0.680, 0.94),
                  (0.630, 0.97), (0.614, 0.87), (0.616, 0.14)])

    # --- 'd' (x: 0.695..0.845) ---
    # Tall horned ascender on right
    polys.append([(0.796, 0.06), (0.768, -0.05), (0.835, 0.02), (0.836, 0.86), (0.858, 0.95),
                  (0.810, 0.96), (0.798, 0.85)])
    # Angular bowl
    polys.append([(0.805, 0.34), (0.725, 0.34), (0.692, 0.58), (0.706, 0.89), (0.762, 0.95),
                  (0.806, 0.88), (0.802, 0.78), (0.762, 0.84), (0.732, 0.77), (0.728, 0.56),
                  (0.752, 0.43), (0.805, 0.44)])

    # --- 't' (x: 0.870..0.990) ---
    # Tall spiked stem
    polys.append([(0.896, 0.11), (0.922, 0.00), (0.940, 0.12), (0.938, 0.84), (0.985, 0.86),
                  (0.955, 0.97), (0.902, 0.93)])
    # Wicked barbed crossbar
    polys.append([(0.862, 0.34), (0.878, 0.27), (0.980, 0.27), (0.996, 0.21), (0.968, 0.38), (0.874, 0.38)])

    return polys


def _flourish_polygon() -> list[tuple[float, float]]:
    """Forked demonic blade swoosh underneath the name."""
    return [
        (0.06, 0.485), (0.28, 0.472), (0.50, 0.466), (0.72, 0.472), (0.94, 0.485),
        (0.98, 0.502), (0.74, 0.494), (0.50, 0.512), (0.26, 0.494), (0.02, 0.502),
    ]


def main() -> None:
    rng = random.Random(666)
    # 1. Obsidian weathered cloth base with vertical drapery & ember hem scorch
    base = Image.new("RGBA", (SW, SH), (16, 12, 20, 255))
    px = base.load()
    for y in range(SH):
        ny = y / float(SH - 1)
        scorch = max(0.0, (ny - 0.60) / 0.40) ** 1.45
        for x in range(SW):
            nx = x / float(SW - 1)
            fold = 0.5 + 0.5 * math.sin(nx * math.pi * 8.0 + ny * 2.2)
            pleat = 0.5 + 0.5 * math.cos(nx * math.pi * 5.0)
            weave = ((x // 4 + y // 4) % 2) * 2
            r = int(14 + 10 * fold + 6 * pleat + 72 * scorch + weave)
            g = int(10 + 5 * fold + 3 * pleat + 6 * scorch + weave)
            b = int(18 + 12 * fold + 6 * pleat - 6 * scorch + weave)
            px[x, y] = (max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)), 255)

    # Subtle weathered scratch/fray lines on cloth
    wdraw = ImageDraw.Draw(base, "RGBA")
    for _ in range(56):
        sx0 = rng.randint(0, SW - 1)
        sy0 = rng.randint(int(SH * 0.50), SH - 1)
        sl = rng.randint(int(SH * 0.08), int(SH * 0.28))
        wdraw.line([(sx0, sy0), (sx0 + rng.randint(-20, 20), min(SH - 1, sy0 + sl))],
                   fill=(110, 18, 28, 78), width=rng.randint(3, 8))

    # 2. Build "Ewaldt" glyph mask in supersampled coordinates
    x0, y0 = SW * 0.08, SH * 0.22
    sx, sy = SW * 0.84, SH * 0.22
    polys = [_poly(p, x0, y0, sx, sy) for p in _ewaldt_polygons()]
    flourish = [(p[0] * SW, p[1] * SH) for p in _flourish_polygon()]

    # Deep drop shadow
    shadow = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow)
    for p in polys + [flourish]:
        sdraw.polygon([(x + 12, y + 18) for x, y in p], fill=(0, 0, 0, 230))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=14))
    base = Image.alpha_composite(base, shadow)

    # Crimson outer demonic glow
    glow = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    for p in polys + [flourish]:
        gdraw.polygon(p, fill=(210, 14, 28, 175))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=22))
    base = Image.alpha_composite(base, glow)

    # Dark iron outline (expanded via blur+threshold or thick line)
    outline = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    odraw = ImageDraw.Draw(outline)
    for p in polys + [flourish]:
        odraw.polygon(p, fill=(14, 5, 8, 255))
        odraw.line(p + [p[0]], fill=(14, 5, 8, 255), width=14, joint="curve")
    base = Image.alpha_composite(base, outline)

    # Metallic molten bone-silver top -> blazing crimson core -> dark blood-iron bottom fill
    mask = Image.new("L", (SW, SH), 0)
    mdraw = ImageDraw.Draw(mask)
    for p in polys + [flourish]:
        mdraw.polygon(p, fill=255)

    grad = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    gpx = grad.load()
    gy0 = int(SH * 0.20)
    gy1 = int(SH * 0.52)
    gspan = max(1, gy1 - gy0)
    for y in range(gy0, min(SH, gy1 + 1)):
        t = max(0.0, min(1.0, (y - gy0) / gspan))
        if t < 0.30:
            k = t / 0.30
            r = 255
            g = int(248 - 140 * k)
            b = int(240 - 165 * k)
        elif t < 0.72:
            k = (t - 0.30) / 0.42
            r = int(255 - 15 * k)
            g = int(108 - 92 * k)
            b = int(75 - 55 * k)
        else:
            k = (t - 0.72) / 0.28
            r = int(240 - 85 * k)
            g = int(16 - 10 * k)
            b = int(20 - 8 * k)
        for x in range(SW):
            gpx[x, y] = (r, g, b, 255)

    fill_layer = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    fill_layer.paste(grad, (0, 0), mask)
    base = Image.alpha_composite(base, fill_layer)

    out = base.convert("RGB").resize((W, H), Image.Resampling.LANCZOS)
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    out.save(OUT_PATH, "PNG", optimize=True)
    print(f"DECAL_SAVED {OUT_PATH} ({W}x{H}, {os.path.getsize(OUT_PATH)} bytes)")


if __name__ == "__main__":
    main()
