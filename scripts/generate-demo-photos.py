#!/usr/bin/env python3
"""Regenerate the synthetic sample photos under assets/demo/.

The Photos page shows these when "Demo mode" is switched on in Settings. They
are flat geometric illustrations drawn from scratch, so nothing in the demo
library can be mistaken for a real person's photo, and the repo carries no
third-party imagery. Requires Pillow: `pip install pillow`.
"""

from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw

OUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "demo"
LANDSCAPE = (800, 600)
PORTRAIT = (600, 800)
QUALITY = 78


def vertical_gradient(size, top, bottom):
    width, height = size
    img = Image.new("RGB", size)
    px = img.load()
    for y in range(height):
        t = y / max(height - 1, 1)
        color = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(width):
            px[x, y] = color
    return img


def polygon_wave(draw, size, baseline, amplitude, period, phase, color):
    width, height = size
    points = [
        (x, baseline + amplitude * math.sin(2 * math.pi * x / period + phase))
        for x in range(0, width + 20, 20)
    ]
    points += [(width, height), (0, height)]
    draw.polygon(points, fill=color)


def stars(draw, size, count, rng, color=(255, 255, 255), ymax=None):
    width, height = size
    ymax = ymax or height
    for _ in range(count):
        x, y = rng.randrange(width), rng.randrange(ymax)
        r = rng.choice((1, 1, 1, 2))
        draw.ellipse((x - r, y - r, x + r, y + r), fill=color)


def sunrise_hills():
    size = LANDSCAPE
    img = vertical_gradient(size, (255, 173, 96), (255, 226, 160))
    d = ImageDraw.Draw(img)
    d.ellipse((330, 250, 470, 390), fill=(255, 244, 214))
    polygon_wave(d, size, 380, 30, 500, 0.0, (214, 122, 88))
    polygon_wave(d, size, 440, 26, 330, 1.2, (168, 84, 74))
    polygon_wave(d, size, 500, 20, 260, 2.4, (110, 52, 60))
    return img


def mountain_lake():
    size = LANDSCAPE
    img = vertical_gradient(size, (120, 176, 232), (206, 230, 246))
    d = ImageDraw.Draw(img)
    d.polygon([(0, 360), (170, 150), (340, 360)], fill=(94, 112, 140))
    d.polygon([(220, 360), (430, 90), (640, 360)], fill=(120, 140, 170))
    d.polygon([(390, 140), (430, 90), (470, 140), (450, 150), (430, 130), (410, 150)], fill=(240, 246, 250))
    d.polygon([(520, 360), (700, 190), (800, 360)], fill=(104, 124, 152))
    d.rectangle((0, 360, 800, 600), fill=(72, 132, 190))
    d.polygon([(220, 360), (430, 630), (640, 360)], fill=(88, 146, 200))
    for y in range(380, 600, 24):
        d.line((0, y, 800, y), fill=(100, 160, 212), width=2)
    return img


def beach():
    size = LANDSCAPE
    img = vertical_gradient(size, (150, 210, 248), (236, 246, 252))
    d = ImageDraw.Draw(img)
    d.ellipse((560, 60, 680, 180), fill=(255, 240, 180))
    d.rectangle((0, 300, 800, 600), fill=(58, 150, 190))
    polygon_wave(d, size, 420, 12, 200, 0.0, (110, 196, 218))
    polygon_wave(d, size, 470, 10, 160, 1.0, (238, 224, 188))
    polygon_wave(d, size, 520, 6, 120, 2.0, (246, 236, 208))
    d.polygon([(90, 600), (110, 300), (130, 600)], fill=(120, 84, 60))
    for angle in range(0, 360, 45):
        rad = math.radians(angle)
        d.line((110, 300, 110 + 90 * math.cos(rad), 300 + 50 * math.sin(rad) - 20), fill=(70, 150, 90), width=14)
    return img


def city_night():
    size = LANDSCAPE
    rng = random.Random(4)
    img = vertical_gradient(size, (14, 18, 56), (60, 40, 110))
    d = ImageDraw.Draw(img)
    stars(d, size, 90, rng, ymax=320)
    d.ellipse((640, 70, 720, 150), fill=(250, 244, 210))
    x = 0
    while x < 800:
        w = rng.randrange(50, 110)
        h = rng.randrange(150, 420)
        d.rectangle((x, 600 - h, x + w, 600), fill=(24, 22, 48))
        for wy in range(600 - h + 14, 590, 22):
            for wx in range(x + 8, x + w - 10, 18):
                if rng.random() < 0.6:
                    d.rectangle((wx, wy, wx + 8, wy + 10), fill=(255, 220, 130))
        x += w + rng.randrange(4, 16)
    return img


def forest_fog():
    size = LANDSCAPE
    img = vertical_gradient(size, (186, 210, 214), (226, 234, 236))
    d = ImageDraw.Draw(img)
    layers = [(400, 130, (120, 154, 140)), (470, 170, (78, 118, 104)), (560, 210, (40, 80, 72))]
    for base, height, color in layers:
        for x in range(-40, 860, 70):
            d.polygon([(x, base), (x + 35, base - height), (x + 70, base)], fill=color)
        d.rectangle((0, base, 800, 600), fill=color)
    return img


def balloons():
    size = LANDSCAPE
    img = vertical_gradient(size, (150, 200, 250), (240, 220, 200))
    d = ImageDraw.Draw(img)
    for cx, cy, r, color in [(200, 220, 90, (232, 84, 96)), (480, 150, 70, (250, 190, 70)), (640, 330, 50, (90, 170, 220)), (330, 400, 40, (140, 200, 120))]:
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=color)
        d.polygon([(cx - r * 0.6, cy + r * 0.6), (cx + r * 0.6, cy + r * 0.6), (cx + 12, cy + r + 40), (cx - 12, cy + r + 40)], fill=color)
        d.rectangle((cx - 14, cy + r + 40, cx + 14, cy + r + 62), fill=(110, 80, 60))
    polygon_wave(d, size, 540, 14, 400, 0.5, (150, 190, 110))
    return img


def desert_dunes():
    size = LANDSCAPE
    img = vertical_gradient(size, (250, 200, 120), (255, 236, 200))
    d = ImageDraw.Draw(img)
    d.ellipse((120, 110, 240, 230), fill=(255, 250, 230))
    polygon_wave(d, size, 340, 40, 600, 0.3, (236, 180, 100))
    polygon_wave(d, size, 420, 36, 420, 2.0, (216, 150, 80))
    polygon_wave(d, size, 500, 30, 300, 4.1, (188, 120, 66))
    return img


def aurora():
    size = PORTRAIT
    rng = random.Random(11)
    img = vertical_gradient(size, (6, 10, 40), (18, 40, 70))
    d = ImageDraw.Draw(img)
    stars(d, size, 160, rng, ymax=620)
    overlay = Image.new("RGBA", size, (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    for i, (baseline, color) in enumerate([(220, (80, 240, 160, 110)), (300, (120, 200, 255, 90)), (380, (180, 120, 255, 80))]):
        points = [(x, baseline + 50 * math.sin(x / 90 + i)) for x in range(0, 620, 10)]
        od.line(points, fill=color, width=70)
    img = Image.alpha_composite(img.convert("RGBA"), overlay).convert("RGB")
    d = ImageDraw.Draw(img)
    for x in range(-20, 640, 60):
        d.polygon([(x, 800), (x + 30, 640), (x + 60, 800)], fill=(10, 20, 30))
    d.rectangle((0, 700, 600, 800), fill=(10, 20, 30))
    return img


def sailboat():
    size = LANDSCAPE
    img = vertical_gradient(size, (236, 150, 110), (250, 214, 150))
    d = ImageDraw.Draw(img)
    d.ellipse((520, 180, 600, 260), fill=(255, 240, 200))
    d.rectangle((0, 330, 800, 600), fill=(60, 110, 150))
    for y in range(350, 600, 20):
        d.line((0, y, 800, y), fill=(84, 134, 172), width=3)
    d.polygon([(300, 460), (500, 460), (470, 500), (330, 500)], fill=(60, 40, 40))
    d.line((400, 460, 400, 250), fill=(60, 40, 40), width=6)
    d.polygon([(400, 250), (400, 450), (300, 450)], fill=(250, 248, 240))
    d.polygon([(410, 250), (410, 450), (490, 450)], fill=(240, 90, 80))
    return img


def lighthouse():
    size = PORTRAIT
    img = vertical_gradient(size, (200, 220, 236), (240, 236, 220))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 520, 600, 800), fill=(70, 120, 160))
    polygon_wave(d, size, 560, 8, 140, 0.0, (100, 150, 190))
    d.polygon([(120, 800), (200, 560), (400, 560), (480, 800)], fill=(120, 110, 100))
    d.polygon([(250, 560), (270, 240), (330, 240), (350, 560)], fill=(245, 245, 240))
    for y in range(280, 560, 70):
        d.polygon([(258 + (y - 240) * 0.06, y), (342 - (y - 240) * 0.06, y), (342 - (y - 240) * 0.06, y + 30), (258 + (y - 240) * 0.06, y + 30)], fill=(220, 70, 60))
    d.rectangle((265, 200, 335, 240), fill=(250, 220, 120))
    d.polygon([(255, 200), (300, 160), (345, 200)], fill=(60, 60, 70))
    return img


def flower_field():
    size = LANDSCAPE
    rng = random.Random(21)
    img = vertical_gradient(size, (170, 210, 250), (230, 240, 250))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 300, 800, 600), fill=(110, 170, 90))
    for _ in range(320):
        x, y = rng.randrange(800), rng.randrange(310, 600)
        r = 3 + (y - 300) // 40
        color = rng.choice([(250, 220, 80), (240, 100, 120), (250, 250, 250), (200, 120, 220)])
        d.ellipse((x - r, y - r, x + r, y + r), fill=color)
    return img


def coffee_flat_lay():
    size = PORTRAIT
    img = Image.new("RGB", size, (232, 214, 190))
    d = ImageDraw.Draw(img)
    for y in range(0, 800, 40):
        d.line((0, y, 600, y), fill=(222, 202, 176), width=6)
    d.ellipse((150, 230, 450, 530), fill=(250, 250, 248))
    d.ellipse((190, 270, 410, 490), fill=(92, 58, 40))
    d.ellipse((230, 300, 330, 380), fill=(120, 80, 56))
    d.ellipse((410, 340, 500, 430), fill=(250, 250, 248))
    d.ellipse((428, 358, 482, 412), fill=(232, 214, 190))
    d.rectangle((90, 560, 320, 700), fill=(60, 80, 110))
    d.rectangle((110, 580, 300, 600), fill=(240, 240, 236))
    return img


PHOTOS = {
    "sunrise-hills.jpg": sunrise_hills,
    "mountain-lake.jpg": mountain_lake,
    "beach-day.jpg": beach,
    "city-night.jpg": city_night,
    "forest-fog.jpg": forest_fog,
    "balloons.jpg": balloons,
    "desert-dunes.jpg": desert_dunes,
    "aurora.jpg": aurora,
    "sailboat.jpg": sailboat,
    "lighthouse.jpg": lighthouse,
    "flower-field.jpg": flower_field,
    "coffee.jpg": coffee_flat_lay,
}


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name, draw in PHOTOS.items():
        path = OUT_DIR / name
        draw().save(path, "JPEG", quality=QUALITY, optimize=True)
        print(f"{name}: {path.stat().st_size} bytes")


if __name__ == "__main__":
    main()
