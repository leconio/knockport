#!/usr/bin/env python3
"""Generate Flutter desktop app icons from the KnockGate logo source."""

from __future__ import annotations

from collections import deque
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/images/knockgate-logo.jpg"
MACOS_DIR = ROOT / "flutter/macos/Runner/Assets.xcassets/AppIcon.appiconset"
IOS_DIR = ROOT / "flutter/ios/Runner/Assets.xcassets/AppIcon.appiconset"
LINUX_ICON = ROOT / "flutter/linux/runner/resources/app_icon.png"
WINDOWS_ICON = ROOT / "flutter/windows/runner/resources/app_icon.ico"
ANDROID_MIPMAPS = {
    "mipmap-mdpi/ic_launcher.png": 48,
    "mipmap-hdpi/ic_launcher.png": 72,
    "mipmap-xhdpi/ic_launcher.png": 96,
    "mipmap-xxhdpi/ic_launcher.png": 144,
    "mipmap-xxxhdpi/ic_launcher.png": 192,
}
IOS_ICONS = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}


def is_background(pixel: tuple[int, int, int]) -> bool:
    r, g, b = pixel
    brightness = max(r, g, b)
    spread = max(r, g, b) - min(r, g, b)
    blue_bias = b - max(r, g)
    # The source has a textured black background and a cyan/steel logo. Flood
    # fill only edge-connected dark pixels so internal keyhole/shadows survive.
    return brightness < 56 or (brightness < 86 and spread < 20 and blue_bias < 14)


def remove_edge_background(source: Image.Image) -> Image.Image:
    rgb = source.convert("RGB")
    width, height = rgb.size
    pixels = rgb.load()
    visited = bytearray(width * height)
    alpha = bytearray([255]) * (width * height)
    queue: deque[tuple[int, int]] = deque()

    def push(x: int, y: int) -> None:
        idx = y * width + x
        if visited[idx]:
            return
        visited[idx] = 1
        if is_background(pixels[x, y]):
            alpha[idx] = 0
            queue.append((x, y))

    for x in range(width):
        push(x, 0)
        push(x, height - 1)
    for y in range(height):
        push(0, y)
        push(width - 1, y)

    while queue:
        x, y = queue.popleft()
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < width and 0 <= ny < height:
                push(nx, ny)

    rgba = rgb.convert("RGBA")
    rgba.putalpha(Image.frombytes("L", (width, height), bytes(alpha)))
    return rgba


def fit_on_canvas(image: Image.Image, size: int, fill_ratio: float = 0.78) -> Image.Image:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise RuntimeError("logo became empty after background removal")
    cropped = image.crop(bbox)
    target = int(size * fill_ratio)
    scale = min(target / cropped.width, target / cropped.height)
    resized = cropped.resize(
        (max(1, round(cropped.width * scale)), max(1, round(cropped.height * scale))),
        Image.Resampling.LANCZOS,
    )
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(resized, ((size - resized.width) // 2, (size - resized.height) // 2))
    return canvas


def opaque_mobile_icon(image: Image.Image, size: int) -> Image.Image:
    background = Image.new("RGBA", (size, size), (5, 10, 14, 255))
    background.alpha_composite(fit_on_canvas(image, size, fill_ratio=0.70))
    return background.convert("RGB")


def save_png(path: Path, image: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "PNG", optimize=True)


def main() -> None:
    transparent_logo = remove_edge_background(Image.open(SOURCE))

    for size in (16, 32, 64, 128, 256, 512, 1024):
        save_png(MACOS_DIR / f"app_icon_{size}.png", fit_on_canvas(transparent_logo, size))

    save_png(LINUX_ICON, fit_on_canvas(transparent_logo, 512))

    android_res = ROOT / "flutter/android/app/src/main/res"
    for relative, size in ANDROID_MIPMAPS.items():
        save_png(android_res / relative, fit_on_canvas(transparent_logo, size))

    for filename, size in IOS_ICONS.items():
        save_png(IOS_DIR / filename, opaque_mobile_icon(transparent_logo, size))

    ico_sizes = [16, 24, 32, 48, 64, 128, 256]
    base = fit_on_canvas(transparent_logo, 256)
    base.save(
        WINDOWS_ICON,
        format="ICO",
        sizes=[(size, size) for size in ico_sizes],
        bitmap_format="png",
    )


if __name__ == "__main__":
    main()
