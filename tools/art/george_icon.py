#!/usr/bin/env python3
"""Saint George and the dragon for the donation bar (GeorgeBar), from an
icon of Sveti Đorđe on gold: George on his white horse and the dragon are
cut from the gold ground, each laid in mosaic (mosaic.py), and written to
client/art/ui/george.png and client/art/ui/dragon.png. Where the dragon sat
under George in the icon is printed: GeorgeBar keeps that when he reaches
it, so the spear meets its jaws as on the icon.

    python3 tools/art/george_icon.py path/to/sveti_djordje.jpg

The cut-out follows the icon this was made from (the outlines below are in
its pixels, 890 x 1081); another picture needs them redrawn. Needs
opencv-python-headless, numpy and Pillow.
"""
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mosaic  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "client" / "art" / "ui"
# George is drawn this tall in the PNG; the dragon at the same scale.
HEIGHT = 320
CELL = 4.5


def cut(bgr: np.ndarray) -> tuple:
    """Masks of George (with his horse) and of the dragon. The rocks under
    them are cut away along their dark cracks, which would break up the
    dragon (its own outlines are as dark): so George comes from a cut with
    the cracks, the dragon from one without."""
    george, _ = _cut(bgr, cracks=True)
    _, dragon = _cut(bgr, cracks=False)
    return (george & (1 - dragon)).astype(np.uint8), dragon


def _cut(bgr: np.ndarray, cracks: bool) -> tuple:
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV).astype(int)
    h, s, v = hsv[..., 0] * 2, hsv[..., 1] / 255, hsv[..., 2] / 255
    H, W = h.shape
    yy, xx = np.mgrid[0:H, 0:W]
    # The gold ground and the rocks below, with their cracks if asked.
    ground = (h >= 20) & (h <= 60) & (s >= 0.2) & (s <= 0.8) & (v >= 0.4)
    if cracks:
        ground |= (yy > 820) & (h >= 10) & (h <= 60) & (v < 0.55) & (s > 0.15)
    # George's fist on the spear is the ground's colour: keep it.
    ground[((xx - 236) / 19.0) ** 2 + ((yy - 112) / 25.0) ** 2 < 1] = False
    # The inscription, top right.
    ground[(yy < 120) & (xx > 540)] = True
    mask = cv2.morphologyEx((ground * 255).astype(np.uint8), cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    # The ground reached from the edges goes; gold inside the figures stays.
    fill = np.zeros((H + 2, W + 2), np.uint8)
    for x in range(0, W, 4):
        for y in (0, H - 1):
            if mask[y, x] == 255:
                cv2.floodFill(mask, fill, (x, y), 128)
    for y in range(0, H, 4):
        for x in (0, W - 1):
            if mask[y, x] == 255:
                cv2.floodFill(mask, fill, (x, y), 128)
    figures = (mask != 128).astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(figures, 8)
    keep = np.zeros_like(figures)
    for i in range(1, count):
        if stats[i, cv2.CC_STAT_AREA] > 4000:
            keep[labels == i] = 1
    # Ground showing through between the spear arm and the cloak, and between
    # the forelegs; and a bush in the corner.
    holes = np.zeros_like(keep)
    cv2.fillPoly(holes, [np.array([(224, 116), (332, 238), (203, 222)], np.int32),
                         np.array([(640, 610), (760, 560), (800, 600), (820, 760), (700, 790), (650, 700)], np.int32)], 1)
    keep[(holes == 1) & ground] = 0
    keep[(yy > 1015) & (xx < 170)] = 0
    # The dragon: its green body, red wings and jaws, below the horse.
    green = (h >= 60) & (h <= 180) & (s > 0.2)
    red = ((h <= 18) | (h >= 340)) & (s > 0.35)
    dragon = np.zeros_like(keep)
    dragon[(green | (red & (yy > 760) & (xx > 360)) | (red & (yy > 700) & (xx > 620))) & (keep == 1) & (yy > 690) & (xx > 190)] = 1
    dragon = cv2.morphologyEx(dragon, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    dragon = cv2.dilate(dragon, np.ones((5, 5), np.uint8)) & keep
    count, labels, stats, _ = cv2.connectedComponentsWithStats(dragon, 8)
    big = np.zeros_like(dragon)
    for i in range(1, count):
        if stats[i, cv2.CC_STAT_AREA] > 3000:
            big[labels == i] = 1
    contours, _ = cv2.findContours(big, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    solid = np.zeros_like(big)
    cv2.drawContours(solid, contours, -1, 1, -1)
    dragon = (solid & keep).astype(np.uint8)
    # George: what is left, without the thin cracks of the rocks under him
    # (his horse's legs are thicker), in one piece.
    george = (keep & (1 - dragon)).astype(np.uint8)
    low = yy > 800
    opened = cv2.morphologyEx(george, cv2.MORPH_OPEN, np.ones((9, 9), np.uint8))
    george[low] = opened[low]
    count, labels, stats, _ = cv2.connectedComponentsWithStats(george, 8)
    largest = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    return (labels == largest).astype(np.uint8), dragon


def piece(rgb: np.ndarray, mask: np.ndarray, scale: float, seed: int) -> tuple:
    """The masked part, cropped, scaled and laid in mosaic, within a ring of
    dark stones that holds it against the parchment; and its box."""
    ring = cv2.dilate(mask, np.ones((9, 9), np.uint8)) - mask
    rgb = rgb.copy()
    rgb[ring == 1] = (52, 34, 22)
    mask = mask | ring
    ys, xs = np.nonzero(mask)
    x0, y0, x1, y1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
    alpha = cv2.GaussianBlur(mask.astype(np.float32), (3, 3), 0)
    rgba = np.dstack([rgb / 255.0, alpha])[y0:y1, x0:x1]
    size = (max(1, round((x1 - x0) * scale)), max(1, round((y1 - y0) * scale)))
    small = cv2.resize(rgba.astype(np.float32), size, interpolation=cv2.INTER_AREA)
    return mosaic.mosaic(np.clip(small, 0, 1), CELL, seed=seed, grout=1.0), (x0, y0, x1, y1)


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    bgr = cv2.imread(sys.argv[1])
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB).astype(np.float64)
    george_mask, dragon_mask = cut(bgr)
    ys, _ = np.nonzero(george_mask)
    scale = HEIGHT / float(ys.max() + 1 - ys.min())
    george, g = piece(rgb, george_mask, scale, 7)
    dragon, d = piece(rgb, dragon_mask, scale, 11)
    OUT.mkdir(parents=True, exist_ok=True)
    george.save(OUT / "george.png", optimize=True)
    dragon.save(OUT / "dragon.png", optimize=True)
    print(f"george {george.size}, dragon {dragon.size}")
    print(f"dragon offset from George (in George's heights): x {(d[0] - g[0]) / (g[3] - g[1]):.4f}, y {(d[1] - g[1]) / (g[3] - g[1]):.4f}")


if __name__ == "__main__":
    main()
