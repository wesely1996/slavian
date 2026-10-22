#!/usr/bin/env python3
"""Presses the studio's mark into a red wax seal for the credits.

Takes client/art/brand/night_forge.png (the mark and "NIGHT FORGE", leaving
out the "SOFTWARE COMPANY" line under it) and writes
client/art/brand/night_forge_seal.png: an uneven disc of red wax with a
pressed face, the mark sunk into it.

    python3 tools/art/seal.py
"""
import math
import random
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
LOGO = ROOT / "client" / "art" / "brand" / "night_forge.png"
OUT = ROOT / "client" / "art" / "brand" / "night_forge_seal.png"

SIZE = 512
# The logo's rows down to the end of "NIGHT FORGE" (the company line is below).
KEEP_ROWS = 342
WAX = (138, 18, 24)
WAX_LIGHT = (186, 40, 42)
WAX_DARK = (74, 6, 12)


def blob(radius: float, wobble: float, seed: int) -> Image.Image:
    """An uneven disc: the wax where it spread under the stamp."""
    rng = random.Random(seed)
    waves = [(rng.randint(3, 9), rng.uniform(0, math.tau), rng.uniform(0.3, 1.0)) for _ in range(5)]
    points = []
    for i in range(360):
        a = math.radians(i)
        r = radius + wobble * sum(amp * math.sin(k * a + phase) for k, phase, amp in waves) / len(waves)
        points.append((SIZE / 2 + r * math.cos(a), SIZE / 2 + r * math.sin(a)))
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    return mask.filter(ImageFilter.GaussianBlur(1.2))


def lit(mask: Image.Image, light: tuple, dark: tuple) -> Image.Image:
    """Fills a shape with light from the top left, falling off to the bottom right."""
    out = Image.new("RGB", (SIZE, SIZE))
    px = out.load()
    for y in range(SIZE):
        for x in range(SIZE):
            t = min(1.0, max(0.0, ((x + y) / (2 * SIZE)) * 1.3 - 0.15))
            px[x, y] = tuple(int(light[c] + (dark[c] - light[c]) * t) for c in range(3))
    return out


def bevel(mask: Image.Image, depth: int, raised: bool) -> Image.Image:
    """Highlight and shadow along a shape's edge (raised or pressed in)."""
    soft = mask.filter(ImageFilter.GaussianBlur(depth))
    up = ImageChops.offset(soft, -depth // 2, -depth // 2)
    down = ImageChops.offset(soft, depth // 2, depth // 2)
    highlight = ImageChops.subtract(soft, down if raised else up)
    shadow = ImageChops.subtract(soft, up if raised else down)
    return highlight, shadow


def main() -> None:
    logo = Image.open(LOGO).convert("RGBA")
    logo = logo.crop((0, 0, logo.width, KEEP_ROWS))
    logo = logo.crop(logo.getbbox())

    wax_mask = blob(232, 16, 7)
    wax = lit(wax_mask, WAX_LIGHT, WAX_DARK)
    seal = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    seal.paste(wax, (0, 0), wax_mask)

    # The outer rim: wax pushed up around the stamp.
    hi, sh = bevel(wax_mask, 14, True)
    seal = Image.composite(Image.new("RGBA", (SIZE, SIZE), (255, 190, 170, 255)), seal, hi.point(lambda v: int(v * 0.45)))
    seal = Image.composite(Image.new("RGBA", (SIZE, SIZE), (40, 0, 0, 255)), seal, sh.point(lambda v: int(v * 0.55)))

    # The stamp's face: a flat disc pressed into the wax.
    face = Image.new("L", (SIZE, SIZE), 0)
    r = 176
    ImageDraw.Draw(face).ellipse((SIZE / 2 - r, SIZE / 2 - r, SIZE / 2 + r, SIZE / 2 + r), fill=255)
    face = face.filter(ImageFilter.GaussianBlur(1.0))
    seal = Image.composite(Image.new("RGBA", (SIZE, SIZE), WAX + (255,)), seal, face.point(lambda v: int(v * 0.85)))
    hi, sh = bevel(face, 8, False)
    seal = Image.composite(Image.new("RGBA", (SIZE, SIZE), (255, 170, 150, 255)), seal, hi.point(lambda v: int(v * 0.5)))
    seal = Image.composite(Image.new("RGBA", (SIZE, SIZE), (50, 0, 0, 255)), seal, sh.point(lambda v: int(v * 0.6)))
    # A ring cut around the face's edge.
    ring = Image.new("L", (SIZE, SIZE), 0)
    rr = r - 16
    ImageDraw.Draw(ring).ellipse((SIZE / 2 - rr, SIZE / 2 - rr, SIZE / 2 + rr, SIZE / 2 + rr), outline=255, width=4)
    hi, sh = bevel(ring, 3, False)
    seal = Image.composite(Image.new("RGBA", (SIZE, SIZE), (70, 4, 6, 255)), seal, ring.point(lambda v: int(v * 0.7)))
    seal = Image.composite(Image.new("RGBA", (SIZE, SIZE), (240, 150, 130, 255)), seal, hi.point(lambda v: int(v * 0.5)))

    # The mark, sunk into the face.
    fit = (rr - 26) * 2
    scale = fit / max(logo.width, logo.height)
    mark = logo.resize((int(logo.width * scale), int(logo.height * scale)), Image.LANCZOS)
    alpha = Image.new("L", (SIZE, SIZE), 0)
    alpha.paste(mark.split()[3], ((SIZE - mark.width) // 2, (SIZE - mark.height) // 2 + 4))
    alpha = alpha.point(lambda v: 255 if v > 70 else int(v * 3.6))
    seal = Image.composite(Image.new("RGBA", (SIZE, SIZE), WAX_DARK + (255,)), seal, alpha.point(lambda v: int(v * 0.8)))
    hi, sh = bevel(alpha, 4, False)
    seal = Image.composite(Image.new("RGBA", (SIZE, SIZE), (250, 165, 145, 255)), seal, hi.point(lambda v: int(v * 0.75)))
    seal = Image.composite(Image.new("RGBA", (SIZE, SIZE), (30, 0, 0, 255)), seal, sh.point(lambda v: int(v * 0.6)))

    # A little grain, and nothing outside the wax.
    rng = random.Random(3)
    grain = Image.new("L", (SIZE, SIZE))
    grain.putdata([128 + rng.randint(-10, 10) for _ in range(SIZE * SIZE)])
    grain = grain.filter(ImageFilter.GaussianBlur(0.8))
    rgb = ImageChops.add(seal.convert("RGB"), grain.convert("RGB"), 1.0, -128)
    out = rgb.convert("RGBA")
    out.putalpha(wax_mask)
    out.save(OUT, optimize=True)
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
