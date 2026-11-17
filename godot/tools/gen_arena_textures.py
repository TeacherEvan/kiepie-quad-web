#!/usr/bin/env python3
"""Generate the extra arena facade textures. Deterministic, PIL-only.

Run from anywhere:  python3 godot/tools/gen_arena_textures.py
Outputs (JPEG to keep the Web pck small):
    godot/assets/tex_facade_garage.jpg
    godot/assets/tex_facade_warehouse.jpg
    godot/assets/tex_facade_depot.jpg
"""

from pathlib import Path
from random import Random

from PIL import Image, ImageDraw

SIZE = 256
OUT = Path(__file__).resolve().parents[1] / "assets"


def grain(img: Image.Image, seed: int, amount: int = 10) -> Image.Image:
    rnd = Random(seed)
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            r, g, b = px[x, y]
            n = rnd.randint(-amount, amount)
            px[x, y] = (
                max(0, min(255, r + n)),
                max(0, min(255, g + n)),
                max(0, min(255, b + n)),
            )
    return img


def garage(seed: int = 11) -> Image.Image:
    """Painted concrete panels: warm grey, panel seams, rust runs."""
    rnd = Random(seed)
    img = Image.new("RGB", (SIZE, SIZE), (126, 116, 102))
    d = ImageDraw.Draw(img)
    for y in range(0, SIZE, 64):
        d.rectangle([0, y, SIZE - 1, y + 2], fill=(88, 80, 70))
        for x in range(0, SIZE, 64):
            d.rectangle([x, y, x + 1, y + 63], fill=(96, 87, 76))
    # rust streaks leaking from the seams
    for _ in range(34):
        x = rnd.randrange(SIZE)
        y = rnd.randrange(0, SIZE, 64) + rnd.randint(1, 6)
        length = rnd.randint(12, 46)
        w = rnd.choice([1, 1, 2])
        d.line([(x, y), (x + rnd.randint(-2, 2), y + length)],
               fill=(rnd.randint(110, 150), rnd.randint(65, 90), rnd.randint(38, 55)),
               width=w)
    # chipped paint patches
    for _ in range(26):
        x, y = rnd.randrange(SIZE), rnd.randrange(SIZE)
        r = rnd.randint(2, 7)
        d.ellipse([x - r, y - r, x + r, y + r],
                  fill=(rnd.randint(94, 112), rnd.randint(86, 102), rnd.randint(74, 90)))
    return grain(img, seed + 1, 8)


def warehouse(seed: int = 23) -> Image.Image:
    """Corrugated steel: vertical ribs, rivets, oxide bloom at the base."""
    rnd = Random(seed)
    img = Image.new("RGB", (SIZE, SIZE), (108, 120, 128))
    px = img.load()
    for x in range(SIZE):
        # triangular rib shading, period 16 px
        phase = (x % 16) / 16.0
        rib = 1.0 - abs(phase - 0.5) * 1.4
        for y in range(SIZE):
            shade = int(rib * 34 - 12)
            base = (108 + shade, 120 + shade, 128 + shade)
            # ground grime gradient
            grime = int((y / SIZE) ** 3 * 34)
            px[x, y] = (max(0, base[0] - grime), max(0, base[1] - grime), max(0, base[2] - grime - 4))
    d = ImageDraw.Draw(img)
    for x in range(8, SIZE, 32):
        d.rectangle([x - 1, 0, x + 1, SIZE - 1], fill=(78, 88, 95))
        for y in range(16, SIZE, 48):
            d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=(64, 72, 78))
    for _ in range(22):
        x, y = rnd.randrange(SIZE), rnd.randrange(SIZE // 2, SIZE)
        r = rnd.randint(4, 12)
        d.ellipse([x - r, y - r // 2, x + r, y + r // 2],
                  fill=(rnd.randint(120, 148), rnd.randint(72, 94), rnd.randint(48, 62)))
    return grain(img, seed + 1, 7)


def depot(seed: int = 37) -> Image.Image:
    """Painted brick: horizontal courses, mortar, faded sign band."""
    rnd = Random(seed)
    img = Image.new("RGB", (SIZE, SIZE), (92, 82, 78))
    d = ImageDraw.Draw(img)
    bh = 24
    for row, y in enumerate(range(0, SIZE, bh)):
        offset = (row % 2) * 22
        for x in range(-44 + offset, SIZE + 44, 44):
            d.rectangle([x + 1, y + 1, x + 42, y + bh - 2],
                        fill=(rnd.randint(126, 150), rnd.randint(94, 112), rnd.randint(78, 92)))
    # old painted band across the upper third
    d.rectangle([0, 46, SIZE - 1, 86], fill=(72, 96, 104))
    d.rectangle([0, 44, SIZE - 1, 46], fill=(52, 70, 76))
    d.rectangle([0, 86, SIZE - 1, 88], fill=(52, 70, 76))
    for _ in range(30):
        x, y = rnd.randrange(SIZE), rnd.randrange(SIZE)
        r = rnd.randint(1, 4)
        d.ellipse([x - r, y - r, x + r, y + r],
                  fill=(rnd.randint(80, 104), rnd.randint(72, 90), rnd.randint(64, 80)))
    return grain(img, seed + 1, 9)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in (
        ("tex_facade_garage.jpg", garage),
        ("tex_facade_warehouse.jpg", warehouse),
        ("tex_facade_depot.jpg", depot),
    ):
        path = OUT / name
        fn().save(path, "JPEG", quality=86, optimize=True)
        print(f"wrote {path} ({path.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
