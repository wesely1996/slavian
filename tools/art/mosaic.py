"""Lays a picture in mosaic, the way the old Serbian churches are (Studenica,
Gračanica, the icons of the Nemanjić era): small stone and glass tesserae,
each one colour, set in dark grout, the gold ones catching the light
unevenly. Used by generate.py for the hero portraits and the logo.

Needs cairosvg (pip install cairosvg) to read the SVG, numpy and Pillow.
"""
import io

import numpy as np
from PIL import Image

GROUT = np.array([58, 44, 30], dtype=float)


def rasterize(svg_text: str, scale: float) -> np.ndarray:
    """The SVG as an RGBA array of floats (0-1), `scale` times its size."""
    import cairosvg

    png = cairosvg.svg2png(bytestring=svg_text.encode(), scale=scale)
    return np.asarray(Image.open(io.BytesIO(png)).convert("RGBA"), dtype=float) / 255.0


def _nearest_seeds(h: int, w: int, cell: float, rng) -> tuple:
    """A jittered grid of tessera centres; for every pixel, its nearest
    centre and how much nearer than the second nearest it is."""
    rows, cols = int(np.ceil(h / cell)) + 1, int(np.ceil(w / cell)) + 1
    # Every other row shifted half a stone, like laid courses.
    offset = (np.arange(rows)[:, None] % 2) * 0.5
    sx = (np.arange(cols)[None, :] + offset + rng.uniform(-0.28, 0.28, (rows, cols))) * cell
    sy = (np.arange(rows)[:, None] + rng.uniform(-0.28, 0.28, (rows, cols))) * cell
    ys, xs = np.mgrid[0:h, 0:w].astype(float)
    gi = np.floor(ys / cell).astype(int)
    gj = np.floor(xs / cell).astype(int)
    best = np.full((h, w), np.inf)
    second = np.full((h, w), np.inf)
    owner = np.zeros((h, w), dtype=int)
    for di in (-1, 0, 1):
        for dj in (-2, -1, 0, 1):
            i = np.clip(gi + di, 0, rows - 1)
            j = np.clip(gj + dj, 0, cols - 1)
            d = np.hypot(xs - sx[i, j], ys - sy[i, j])
            closer = d < best
            second = np.where(closer, best, np.minimum(second, d))
            owner = np.where(closer, i * cols + j, owner)
            best = np.where(closer, d, best)
    return owner, second - best, rows * cols


def _is_gold(rgb: np.ndarray) -> np.ndarray:
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    return (r > 0.55) & (g > 0.4) & (b < g * 0.75) & (r - b > 0.25)


def mosaic(image: np.ndarray, cell: float, seed: int = 1, grout: float = 1.4) -> Image.Image:
    """`image` (RGBA floats) laid in tesserae about `cell` pixels across."""
    rng = np.random.default_rng(seed)
    h, w = image.shape[:2]
    owner, margin, count = _nearest_seeds(h, w, cell, rng)
    flat = owner.ravel()
    alpha = image[..., 3].ravel()
    weight = np.bincount(flat, alpha, count) + 1e-6
    colour = np.stack([np.bincount(flat, image[..., c].ravel() * alpha, count) / weight for c in range(3)], axis=1)
    # Each stone a shade apart from its neighbours; gold ones more so, as
    # gold leaf under glass catches the light at its own angle.
    gold = _is_gold(colour[None, :, :])[0]
    jitter = rng.normal(0, 0.035, count) + np.where(gold, rng.normal(0, 0.07, count), 0)
    colour = np.clip(colour * (1 + jitter[:, None]), 0, 1)
    out = colour[owner]
    # Light from the upper left across each stone: a little bevel.
    ys, xs = np.mgrid[0:h, 0:w].astype(float)
    centre_y = np.bincount(flat, ys.ravel(), count) / (np.bincount(flat, minlength=count) + 1e-6)
    centre_x = np.bincount(flat, xs.ravel(), count) / (np.bincount(flat, minlength=count) + 1e-6)
    lit = ((centre_x[owner] - xs) + (centre_y[owner] - ys)) / (cell * 1.4)
    out = np.clip(out * (1 + 0.1 * lit[..., None]), 0, 1)
    # Grout between the stones.
    joint = np.clip((grout - margin) / grout, 0, 1)[..., None]
    out = out * (1 - joint * 0.85) + (GROUT / 255.0) * joint * 0.85
    # The picture keeps its own clean edge; the grout shows a little within.
    a = image[..., 3] * (1 - joint[..., 0] * 0.3)
    rgba = np.dstack([out, a])
    return Image.fromarray((rgba * 255).astype(np.uint8), "RGBA")
