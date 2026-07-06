#!/usr/bin/env python3
"""Render Barys VPN adaptive icon previews for common launcher shapes."""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FG_PATH = ROOT / "client/android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png"
OUT_DIR = ROOT / "docs/icon-previews"
BG = (11, 21, 40)  # #0B1528
INSET = 0.16
SIZE = 512
PAD = 48
LABEL_H = 56


def compose_adaptive_icon(size: int = SIZE) -> Image.Image:
    fg = Image.open(FG_PATH).convert("RGBA")
    canvas = Image.new("RGBA", (size, size), BG + (255,))
    margin = int(size * INSET)
    inner = size - 2 * margin
    fg_resized = fg.resize((inner, inner), Image.Resampling.LANCZOS)
    canvas.paste(fg_resized, (margin, margin), fg_resized)
    return canvas


def mask_circle(size: int) -> Image.Image:
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).ellipse((0, 0, size - 1, size - 1), fill=255)
    return m


def mask_rounded_rect(size: int, radius_ratio: float) -> Image.Image:
    m = Image.new("L", (size, size), 0)
    r = int(size * radius_ratio)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size - 1, size - 1), radius=r, fill=255)
    return m


def mask_squircle(size: int) -> Image.Image:
    """Approximate Samsung / One UI squircle (superellipse n≈4)."""
    m = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(m)
    cx = cy = (size - 1) / 2
    a = b = (size - 1) / 2
    n = 4.0
    for y in range(size):
        for x in range(size):
            nx = abs(x - cx) / a
            ny = abs(y - cy) / b
            if nx**n + ny**n <= 1.0:
                m.putpixel((x, y), 255)
    return m


def mask_teardrop(size: int) -> Image.Image:
    """Some OEM launchers use a teardrop / rounded-top shape."""
    m = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(m)
    r = int(size * 0.5)
    draw.ellipse((0, 0, size - 1, size - 1), fill=255)
    # Flatten bottom slightly
    draw.rectangle((int(size * 0.08), int(size * 0.72), int(size * 0.92), size - 1), fill=255)
    return m


def apply_mask(icon: Image.Image, mask: Image.Image) -> Image.Image:
    out = Image.new("RGBA", icon.size, (0, 0, 0, 0))
    out.paste(icon, (0, 0), mask)
    return out


def draw_label(img: Image.Image, text: str, sub: str = "") -> Image.Image:
    w, h = img.size
    out = Image.new("RGBA", (w, h + LABEL_H), (18, 18, 24, 255))
    out.paste(img, (0, 0))
    draw = ImageDraw.Draw(out)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 22)
        font_sm = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 14)
    except OSError:
        font = ImageFont.load_default()
        font_sm = font
    draw.text((w // 2, h + 8), text, fill=(240, 240, 245), anchor="mt", font=font)
    if sub:
        draw.text((w // 2, h + 34), sub, fill=(160, 160, 170), anchor="mt", font=font_sm)
    return out


def on_checkerboard(icon: Image.Image, cell: int = 16) -> Image.Image:
    """Show icon on light/dark checkerboard (like Play Console)."""
    w, h = icon.size
    bg = Image.new("RGBA", (w, h), (255, 255, 255, 255))
    draw = ImageDraw.Draw(bg)
    c1, c2 = (230, 230, 235), (200, 200, 210)
    for y in range(0, h, cell):
        for x in range(0, w, cell):
            draw.rectangle(
                (x, y, x + cell - 1, y + cell - 1),
                fill=c1 if (x // cell + y // cell) % 2 == 0 else c2,
            )
    bg.paste(icon, (0, 0), icon)
    return bg


PRESETS = [
    ("pixel_circle", "Google Pixel", "круг (Adaptive Icon)", mask_circle),
    ("stock_android", "Stock Android 13+", "круг / скруглённый", mask_circle),
    ("samsung_squircle", "Samsung One UI", "squircle", mask_squircle),
    ("rounded_square", "Xiaomi / Huawei", "скруглённый квадрат", lambda s: mask_rounded_rect(s, 0.22)),
    ("legacy_square", "Старый Android (<8)", "квадрат без маски", None),
    ("ios_rounded", "iOS", "скруглённый квадрат ~22%", lambda s: mask_rounded_rect(s, 0.223)),
]


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    icon = compose_adaptive_icon()

    tiles: list[Image.Image] = []
    for slug, title, subtitle, mask_fn in PRESETS:
        if mask_fn is None:
            rendered = icon.copy()
        else:
            mask = mask_fn(SIZE)
            rendered = apply_mask(icon, mask)
        rendered = on_checkerboard(rendered)
        labeled = draw_label(rendered, title, subtitle)
        labeled.save(OUT_DIR / f"{slug}.png")
        tiles.append(labeled)
        print(f"  {OUT_DIR / f'{slug}.png'}")

    # Grid: 3 columns x 2 rows
    cols, rows = 3, 2
    tw, th = tiles[0].size
    grid = Image.new("RGBA", (cols * tw + PAD * (cols + 1), rows * th + PAD * (rows + 1)), (18, 18, 24, 255))
    title_bar = 72
    grid_full = Image.new(
        "RGBA",
        (grid.width, grid.height + title_bar),
        (18, 18, 24, 255),
    )
    draw = ImageDraw.Draw(grid_full)
    try:
        title_font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 28)
    except OSError:
        title_font = ImageFont.load_default()
    draw.text(
        (grid_full.width // 2, 20),
        "Barys VPN — превью иконки на разных устройствах",
        fill=(255, 255, 255),
        anchor="mt",
        font=title_font,
    )
    draw.text(
        (grid_full.width // 2, 52),
        "Adaptive icon: фон #0B1528 + foreground inset 16%",
        fill=(140, 200, 220),
        anchor="mt",
        font=title_font,
    )
    grid_full.paste(grid, (0, title_bar))

    for i, tile in enumerate(tiles):
        col, row = i % cols, i // cols
        x = PAD + col * (tw + PAD)
        y = title_bar + PAD + row * (th + PAD)
        grid_full.paste(tile, (x, y))

    out_grid = OUT_DIR / "all-devices-grid.png"
    grid_full.save(out_grid)
    print(f"  {out_grid}")


if __name__ == "__main__":
    main()
