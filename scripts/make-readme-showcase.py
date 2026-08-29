#!/usr/bin/env python3
"""Compose a README hero from real, privacy-sanitized app screenshots."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


CANVAS_SIZE = (1920, 1200)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--overview", type=Path, required=True)
    parser.add_argument("--diagnostics", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def font(size: int, weight: str = "regular") -> ImageFont.FreeTypeFont:
    candidates = {
        "regular": [
            "/System/Library/Fonts/SFNS.ttf",
            "/System/Library/Fonts/Helvetica.ttc",
        ],
        "bold": [
            "/System/Library/Fonts/SFNS.ttf",
            "/System/Library/Fonts/Helvetica.ttc",
        ],
    }
    for candidate in candidates[weight]:
        path = Path(candidate)
        if path.exists():
            return ImageFont.truetype(str(path), size=size)
    return ImageFont.load_default()


def cover(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], fill: tuple[int, int, int]) -> None:
    draw.rounded_rectangle(box, radius=4, fill=fill)


def sanitize_overview(source: Path) -> Image.Image:
    image = Image.open(source).convert("RGB")
    if image.size != (1040, 700):
        raise ValueError(f"Unexpected overview size: {image.size}")
    draw = ImageDraw.Draw(image)

    # The pointer is intentionally parked in the empty top-right area for capture.
    cover(draw, (972, 72, 1038, 145), (255, 255, 255))

    # Hide machine-local port, PID, event times, and loopback URL.
    cover(draw, (322, 213, 445, 231), (230, 234, 235))
    cover(draw, (797, 213, 914, 231), (230, 234, 235))
    for top in (544, 577, 609, 642):
        cover(draw, (956, top, 1004, top + 19), (230, 234, 235))
    cover(draw, (18, 662, 207, 687), (234, 238, 239))
    return image


def sanitize_diagnostics(source: Path) -> Image.Image:
    image = Image.open(source).convert("RGB")
    if image.size != (1040, 700):
        raise ValueError(f"Unexpected diagnostics size: {image.size}")
    draw = ImageDraw.Draw(image)

    # The pointer is intentionally parked in the empty top-right area for capture.
    cover(draw, (972, 72, 1038, 145), (255, 255, 255))

    # Hide exact check time, disk capacity, PID, and loopback URL.
    cover(draw, (346, 205, 583, 225), (230, 234, 235))
    cover(draw, (307, 452, 501, 471), (230, 234, 235))
    cover(draw, (307, 558, 532, 578), (230, 234, 235))
    cover(draw, (18, 662, 207, 687), (234, 238, 239))
    return image


def gradient_background(size: tuple[int, int]) -> Image.Image:
    width, height = size
    top = (248, 249, 255)
    bottom = (238, 241, 249)
    image = Image.new("RGB", size)
    pixels = image.load()
    for y in range(height):
        ratio = y / max(height - 1, 1)
        row = tuple(round(a + (b - a) * ratio) for a, b in zip(top, bottom))
        for x in range(width):
            pixels[x, y] = row
    return image


def add_glow(canvas: Image.Image, box: tuple[int, int, int, int], color: tuple[int, int, int, int]) -> None:
    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse(box, fill=color)
    glow = glow.filter(ImageFilter.GaussianBlur(110))
    canvas.alpha_composite(glow)


def rounded_window(image: Image.Image, width: int, radius: int = 24) -> Image.Image:
    height = round(width * image.height / image.width)
    resized = image.resize((width, height), Image.Resampling.LANCZOS).convert("RGBA")
    mask = Image.new("L", resized.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, width - 1, height - 1), radius=radius, fill=255)
    resized.putalpha(mask)
    return resized


def place_window(canvas: Image.Image, window: Image.Image, position: tuple[int, int], shadow_radius: int) -> None:
    x, y = position
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_shape = Image.new("L", window.size, 0)
    ImageDraw.Draw(shadow_shape).rounded_rectangle(
        (0, 0, window.width - 1, window.height - 1), radius=24, fill=190
    )
    shadow_shape = shadow_shape.filter(ImageFilter.GaussianBlur(shadow_radius))
    shadow_color = Image.new("RGBA", window.size, (43, 47, 70, 95))
    shadow_color.putalpha(shadow_shape)
    shadow.alpha_composite(shadow_color, (x + 2, y + 18))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(window, position)

    border = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle(
        (x, y, x + window.width - 1, y + window.height - 1),
        radius=24,
        outline=(255, 255, 255, 210),
        width=2,
    )
    canvas.alpha_composite(border)


def compose(overview: Image.Image, diagnostics: Image.Image) -> Image.Image:
    canvas = gradient_background(CANVAS_SIZE).convert("RGBA")
    add_glow(canvas, (-240, -270, 760, 730), (126, 105, 255, 75))
    add_glow(canvas, (1280, 330, 2200, 1260), (57, 189, 235, 54))

    draw = ImageDraw.Draw(canvas)
    draw.text((92, 62), "OpenCodex Desktop", font=font(48, "bold"), fill=(24, 26, 38, 255))
    draw.text(
        (94, 121),
        "Native runtime control  ·  diagnostics  ·  repair",
        font=font(24),
        fill=(91, 96, 116, 255),
    )
    draw.rounded_rectangle((1677, 74, 1828, 119), radius=22, fill=(255, 255, 255, 185))
    draw.text((1703, 84), "macOS", font=font(20, "bold"), fill=(83, 76, 214, 255))

    overview_window = rounded_window(overview, 1240)
    diagnostics_window = rounded_window(diagnostics, 880)
    place_window(canvas, overview_window, (78, 214), shadow_radius=28)
    place_window(canvas, diagnostics_window, (958, 500), shadow_radius=24)
    return canvas.convert("RGB")


def main() -> None:
    args = parse_args()
    overview = sanitize_overview(args.overview)
    diagnostics = sanitize_diagnostics(args.diagnostics)
    result = compose(overview, diagnostics)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    result.save(args.output, format="PNG", optimize=True)
    print(f"Wrote {args.output} ({result.width}x{result.height})")


if __name__ == "__main__":
    main()
