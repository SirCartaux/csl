#!/usr/bin/env python3
"""Generates Resources/CSL.icns — a 32x32 pixel-art magnifier, nearest-neighbour scaled."""
from pathlib import Path
import subprocess
from PIL import Image

GRID = 32
BG = (14, 14, 22, 255)
CREAM = (237, 230, 214, 255)
AMBER = (255, 194, 75, 255)
DIM = (59, 59, 85, 255)


def build() -> Image.Image:
    img = Image.new("RGBA", (GRID, GRID), BG)
    px = img.load()

    # hand-drawn border, one pixel, slightly lighter than the surface
    for i in range(GRID):
        px[i, 0] = DIM
        px[i, GRID - 1] = DIM
        px[0, i] = DIM
        px[GRID - 1, i] = DIM

    cx, cy = 13.0, 12.5
    # handle first, so the ring sits on top of it
    for y in range(19, 29):
        for x in range(19, 29):
            if abs(x - y) <= 2:
                px[x, y] = AMBER

    # lens ring
    for y in range(GRID):
        for x in range(GRID):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if 6.6 <= d <= 9.1:
                px[x, y] = CREAM

    # glint inside the glass
    px[8, 8] = AMBER
    px[9, 7] = AMBER
    px[7, 9] = AMBER

    return img


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    iconset = root / "build" / "CSL.iconset"
    iconset.mkdir(parents=True, exist_ok=True)
    art = build()
    art.resize((512, 512), Image.NEAREST).save("/tmp/csl-icon-preview.png")

    for size in (16, 32, 64, 128, 256, 512, 1024):
        art.resize((size, size), Image.NEAREST).save(iconset / f"icon_{size}x{size}.png")
        art.resize((size * 2, size * 2), Image.NEAREST).save(iconset / f"icon_{size}x{size}@2x.png")

    subprocess.run(
        ["iconutil", "-c", "icns", str(iconset), "-o", str(root / "Resources" / "CSL.icns")],
        check=True,
    )
    print("wrote Resources/CSL.icns")


if __name__ == "__main__":
    main()
