#!/usr/bin/env python3
"""Makes the parchment the sheets are drawn on: a seamless 256 px tile of
warm, uneven paper with fibres and faint stains (client/art/ui/parchment.png).
The torn, darkened edges are drawn around it in the game (Parchment).

    python3 tools/art/parchment.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "client" / "art" / "ui" / "parchment.png"
SIZE = 256
LIGHT = np.array([236, 224, 194], dtype=float)
DARK = np.array([214, 194, 150], dtype=float)


def periodic_noise(rng, cells):
    """Smooth noise that wraps at the tile's edges: random values on a
    `cells` grid, interpolated with a cosine, wrapping around."""
    grid = rng.random((cells, cells))
    t = np.arange(SIZE) * cells / SIZE
    i0 = np.floor(t).astype(int)
    f = (1 - np.cos((t - i0) * np.pi)) / 2
    i1 = (i0 + 1) % cells
    rows = grid[i0][:, i0] * (1 - f)[None, :] + grid[i0][:, i1] * f[None, :]
    rows_next = grid[i1][:, i0] * (1 - f)[None, :] + grid[i1][:, i1] * f[None, :]
    return rows * (1 - f)[:, None] + rows_next * f[:, None]


def main() -> None:
    rng = np.random.default_rng(11)
    # Broad blotches and finer mottling.
    tone = 0.55 * periodic_noise(rng, 4) + 0.3 * periodic_noise(rng, 8) + 0.15 * periodic_noise(rng, 32)
    tone = (tone - tone.min()) / (tone.max() - tone.min())
    # Fibres: short streaks of slightly darker paper, mostly along the grain.
    fibres = np.zeros((SIZE, SIZE))
    for _ in range(420):
        x, y = rng.integers(0, SIZE, 2)
        length = rng.integers(6, 22)
        angle = rng.normal(0.15, 0.35)
        for s in range(length):
            fx = int(x + s * np.cos(angle)) % SIZE
            fy = int(y + s * np.sin(angle)) % SIZE
            fibres[fy, fx] += rng.uniform(0.25, 0.6)
    fibres = np.clip(fibres, 0, 1)
    # Grain: a little per-pixel speckle.
    grain = rng.normal(0, 1, (SIZE, SIZE))
    mix = np.clip(tone * 0.75 + fibres * 0.18 + grain * 0.03, 0, 1)
    rgb = LIGHT[None, None, :] * (1 - mix[..., None]) + DARK[None, None, :] * mix[..., None]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB").save(OUT, optimize=True)
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
