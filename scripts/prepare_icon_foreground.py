#!/usr/bin/env python3
"""Build a transparent foreground asset that fills the adaptive icon shape."""

from __future__ import annotations

from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "client/assets/icon.png"
OUT = ROOT / "client/assets/icon_foreground.png"
BG_RGB = (11, 21, 40)  # #0B1528
BG_TOLERANCE = 55
FILL_RATIO = 0.96
OUT_SIZE = 1024


def color_distance(a: tuple[int, int, int], b: tuple[int, int, int]) -> float:
    return ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2) ** 0.5


def is_background(rgb: tuple[int, int, int]) -> bool:
    return color_distance(rgb, BG_RGB) <= BG_TOLERANCE


def flood_remove_background(img: Image.Image) -> Image.Image:
    """Remove background connected to image edges (keeps interior dark pixels)."""
    rgba = img.convert("RGBA")
    w, h = rgba.size
    px = rgba.load()
    visited = [[False] * w for _ in range(h)]
    q: deque[tuple[int, int]] = deque()

    for x in range(w):
        q.append((x, 0))
        q.append((x, h - 1))
    for y in range(h):
        q.append((0, y))
        q.append((w - 1, y))

    while q:
        x, y = q.popleft()
        if x < 0 or y < 0 or x >= w or y >= h or visited[x][y]:
            continue
        visited[x][y] = True
        r, g, b, a = px[x, y]
        if a == 0 or not is_background((r, g, b)):
            continue
        px[x, y] = (r, g, b, 0)
        q.append((x + 1, y))
        q.append((x - 1, y))
        q.append((x, y + 1))
        q.append((x, y - 1))

    return rgba


def bbox_opaque(img: Image.Image) -> tuple[int, int, int, int]:
    alpha = img.split()[3]
    return alpha.getbbox() or (0, 0, img.width, img.height)


def center_on_canvas(content: Image.Image, size: int, fill_ratio: float) -> Image.Image:
    cropped = content.crop(bbox_opaque(content))
    target = int(size * fill_ratio)
    cw, ch = cropped.size
    scale = min(target / cw, target / ch)
    nw, nh = max(1, int(cw * scale)), max(1, int(ch * scale))
    resized = cropped.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(resized, ((size - nw) // 2, (size - nh) // 2), resized)
    return canvas


def main() -> None:
    src = Image.open(SRC)
    fg = flood_remove_background(src)
    fg = center_on_canvas(fg, OUT_SIZE, FILL_RATIO)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    fg.save(OUT)
    print(f"Wrote {OUT} ({OUT_SIZE}x{OUT_SIZE}, fill={FILL_RATIO:.0%})")


if __name__ == "__main__":
    main()
