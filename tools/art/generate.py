#!/usr/bin/env python3
"""Generates Slavian's first set of art as SVG (docs/art-style.md).

Every asset is built from the same palette and the same few rules (a dark
outline, flat fills with one highlight, a soft ground shadow), so the set
stays consistent. Files go to client/art/generated/; client/art/art.json maps
art ids to files. Entries that point somewhere else (your own art) are never
touched, so you can replace any asset by pointing its id at your file.

    python3 tools/art/generate.py
"""
import itertools
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "client" / "art" / "generated"
MANIFEST = ROOT / "client" / "art" / "art.json"
RES = "res://art/generated"

# --- Palette ---------------------------------------------------------------
INK = "#2b2118"          # every outline
SHADOW = "#2b2118"
P = {
    "grass": ("#7fa04a", "#9dbb5f"),
    "meadow": ("#a7b25a", "#c2c977"),
    "forest": ("#3f6b35", "#5a8a45"),
    "dark_forest": ("#22392a", "#355640"),
    "hill": ("#9a8455", "#b7a06c"),
    "rock": ("#7c776f", "#a6a097"),
    "snow": ("#eef3f5", "#ffffff"),
    "ice": ("#cfdfe6", "#e9f2f5"),
    "water": ("#3f7f9e", "#6aa6c2"),
    "deep": ("#2a5873", "#3f7f9e"),
    "swamp": ("#5e6b45", "#76845a"),
    "mud": ("#5a6a55", "#6f8170"),
    "sand": ("#c8ad6a", "#dcc68a"),
    "hallow": ("#9e8a86", "#bba7a2"),
    "wood": ("#8b5a2b", "#b07a45"),
    "thatch": ("#c9a55a", "#e3c27a"),
    "roof": ("#b5452f", "#d26a4c"),
    "stone": ("#a39d93", "#c8c2b8"),
    "wall": ("#ede4cf", "#fbf6ea"),
    "gold": ("#e2b33c", "#f6d572"),
    "ember": ("#e8642c", "#ffb347"),
    "iron": ("#5d6672", "#8d98a6"),
    "cloth": ("#f4f1ea", "#ffffff"),
    "red": ("#a83a2c", "#cf5a44"),
    "night": ("#1f1a2a", "#3a3150"),
    "bone": ("#e6dcc2", "#f6efdc"),
}
STROKE = 4
# SVGs are imported at twice their size, so the map stays sharp when zoomed in.
IMPORT_SCALE = 2.0


def fmt(v):
    return f"{v:.1f}".rstrip("0").rstrip(".")


def pts(points):
    return " ".join(f"{fmt(x)},{fmt(y)}" for x, y in points)


# Gradient ids, unique across pieces so one can be drawn inside another.
GRADIENT_IDS = itertools.count()


class Svg:
    def __init__(self, w=128, h=128):
        self.w, self.h = w, h
        self.parts = []
        self.defs = []

    def lin(self, stops, x1=0, y1=0, x2=0, y2=1):
        """A linear gradient (in the shape's own box, 0-1) to fill with:
        stops are (offset, colour) or (offset, colour, opacity)."""
        gid = f"g{next(GRADIENT_IDS)}"
        self.defs.append(f'<linearGradient id="{gid}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">{self._stops(stops)}</linearGradient>')
        return f"url(#{gid})"

    def rad(self, stops, cx=0.5, cy=0.5, r=0.5, fx=None, fy=None):
        gid = f"g{next(GRADIENT_IDS)}"
        focus = f' fx="{fx}" fy="{fy}"' if fx is not None else ""
        self.defs.append(f'<radialGradient id="{gid}" cx="{cx}" cy="{cy}" r="{r}"{focus}>{self._stops(stops)}</radialGradient>')
        return f"url(#{gid})"

    @staticmethod
    def _stops(stops):
        out = []
        for stop in stops:
            opacity = f' stop-opacity="{stop[2]}"' if len(stop) > 2 else ""
            out.append(f'<stop offset="{stop[0]}" stop-color="{stop[1]}"{opacity}/>')
        return "".join(out)

    def add(self, s):
        self.parts.append(s)
        return self

    def poly(self, points, fill, stroke=INK, sw=STROKE, opacity=1):
        return self.add(f'<polygon points="{pts(points)}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round" opacity="{opacity}"/>')

    def path(self, d, fill, stroke=INK, sw=STROKE, opacity=1, cap="round"):
        return self.add(f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round" stroke-linecap="{cap}" opacity="{opacity}"/>')

    def circle(self, cx, cy, r, fill, stroke=INK, sw=STROKE, opacity=1):
        return self.add(f'<circle cx="{fmt(cx)}" cy="{fmt(cy)}" r="{fmt(r)}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" opacity="{opacity}"/>')

    def ellipse(self, cx, cy, rx, ry, fill, stroke=INK, sw=STROKE, opacity=1):
        return self.add(f'<ellipse cx="{fmt(cx)}" cy="{fmt(cy)}" rx="{fmt(rx)}" ry="{fmt(ry)}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" opacity="{opacity}"/>')

    def rect(self, x, y, w, h, fill, stroke=INK, sw=STROKE, rx=0, opacity=1):
        return self.add(f'<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(h)}" rx="{fmt(rx)}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round" opacity="{opacity}"/>')

    def line(self, x1, y1, x2, y2, stroke=INK, sw=STROKE, opacity=1):
        # A gradient sized to the shape's box has nothing to span on a level
        # or upright line, and SVG then draws nothing: use its middle colour.
        if stroke.startswith("url(") and (x1 == x2 or y1 == y2):
            stroke = "#e6dcc2"
        return self.add(f'<line x1="{fmt(x1)}" y1="{fmt(y1)}" x2="{fmt(x2)}" y2="{fmt(y2)}" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" opacity="{opacity}"/>')

    def shadow(self, cx, cy, rx, ry=None):
        return self.ellipse(cx, cy, rx, ry if ry is not None else rx * 0.28, SHADOW, stroke="none", sw=0, opacity=0.25)

    def embed(self, other, x, y, scale=1.0):
        """Draws another piece inside this one, its top left at (x, y)."""
        self.defs.extend(other.defs)
        body = "".join(other.parts)
        return self.add(f'<g transform="translate({fmt(x)},{fmt(y)}) scale({scale})">{body}</g>')

    def text(self):
        body = "\n  ".join(([f"<defs>{''.join(self.defs)}</defs>"] if self.defs else []) + self.parts)
        return f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" viewBox="0 0 {self.w} {self.h}">\n  {body}\n</svg>\n'


# --- Shared pieces -----------------------------------------------------------


def tuft(s, x, y, color=INK, size=8):
    s.path(f"M{fmt(x - size * 0.6)},{fmt(y)} L{fmt(x - size * 0.3)},{fmt(y - size)} M{fmt(x)},{fmt(y)} L{fmt(x)},{fmt(y - size * 1.2)} M{fmt(x + size * 0.6)},{fmt(y)} L{fmt(x + size * 0.3)},{fmt(y - size)}", "none", stroke=color, sw=2.5)


def icon(kind):
    """Line icons for buttons: white strokes the theme tints."""
    s = Svg(64, 64)
    W = "#ffffff"

    def stroke(d, sw=4.5):
        s.path(d, "none", stroke=W, sw=sw)

    if kind == "back":
        stroke("M38,14 L20,32 L38,50", 6)
    elif kind == "map":
        stroke("M8,16 L24,10 L40,16 L56,10 L56,48 L40,54 L24,48 L8,54 Z")
        stroke("M24,10 L24,48 M40,16 L40,54", 3)
    elif kind == "village":
        stroke("M10,30 L32,12 L54,30")
        stroke("M16,26 L16,52 L48,52 L48,26")
        stroke("M27,52 L27,38 L37,38 L37,52", 3.5)
    elif kind == "inbox":
        stroke("M8,16 L56,16 L56,48 L8,48 Z")
        stroke("M8,18 L32,36 L56,18", 3.5)
    elif kind == "threat":
        stroke("M14,50 L46,18 M40,14 L50,24 M18,40 L24,46")
        stroke("M50,50 L18,18 M24,14 L14,24 M46,40 L40,46")
    elif kind == "build":
        stroke("M12,52 L36,28", 6)
        stroke("M28,12 L46,8 L56,26 L40,34 Z", 4)
    elif kind == "troops":
        stroke("M14,12 L50,12 L50,30 Q50,48 32,56 Q14,48 14,30 Z")
        stroke("M32,20 L32,46 M22,30 L42,30", 3.5)
    elif kind == "caravan":
        stroke("M8,40 L50,40 L50,24 L8,24 Z")
        stroke("M50,32 L58,32", 3.5)
        s.circle(18, 46, 6, "none", stroke=W, sw=4)
        s.circle(40, 46, 6, "none", stroke=W, sw=4)
    elif kind == "research":
        stroke("M32,16 Q20,10 8,14 L8,50 Q20,46 32,52 Q44,46 56,50 L56,14 Q44,10 32,16 Z")
        stroke("M32,16 L32,52", 3)
    elif kind == "clock":
        s.circle(32, 32, 22, "none", stroke=W, sw=4.5)
        stroke("M32,18 L32,32 L42,38", 4)
    return s


UI_ICONS = ["back", "map", "village", "inbox", "threat", "build", "troops", "caravan", "research", "clock"]


# --- Map features: shaded, outline-free, lit from the upper left ------------------
# Drawn over the ground by MapFeatures (client/scripts/map/map_features.gd),
# several to a hex; each one's foot is at the bottom centre of its picture.

def soft_shadow(s, cx, cy, rx, ry, strength=0.38):
    s.ellipse(cx, cy, rx, ry, s.rad([(0, "#000000", strength), (1, "#000000", 0)]), stroke="none", sw=0)


def conifer(s, x, foot, w, h, colors, tiers=3):
    """A pine: tiers of needles, lit on the left."""
    soft_shadow(s, x + w * 0.1, foot - 2, w * 0.42, w * 0.12)
    s.rect(x - w * 0.06, foot - h * 0.22, w * 0.12, h * 0.2, s.lin([(0, "#7a5636"), (1, "#3b2817")], 0, 0, 1, 0), stroke="none", sw=0)
    light, mid, dark = colors
    for i in range(tiers):
        top = foot - h + i * h * 0.24
        bottom = foot - h * 0.18 - (tiers - 1 - i) * h * 0.16
        half = w * (0.26 + 0.12 * i)
        fill = s.lin([(0, light), (0.45, mid), (1, dark)], 0, 0, 1, 0)
        s.path(f"M{fmt(x)},{fmt(top)} Q{fmt(x - half * 0.35)},{fmt((top + bottom) / 2)} {fmt(x - half)},{fmt(bottom)} "
               f"Q{fmt(x)},{fmt(bottom + h * 0.05)} {fmt(x + half)},{fmt(bottom)} Q{fmt(x + half * 0.35)},{fmt((top + bottom) / 2)} {fmt(x)},{fmt(top)} Z",
               fill, stroke="none", sw=0)
        s.path(f"M{fmt(x - half * 0.92)},{fmt(bottom - 1)} Q{fmt(x)},{fmt(bottom + h * 0.035)} {fmt(x + half * 0.92)},{fmt(bottom - 1)}",
               "none", stroke="#000000", sw=1.6, opacity=0.18)


def f_pine():
    s = Svg(64, 96)
    conifer(s, 32, 92, 56, 88, ("#7f9a52", "#4f6b37", "#2b3f24"))
    return s


def f_dark_pine():
    s = Svg(56, 100)
    conifer(s, 28, 96, 46, 94, ("#56705a", "#2f4634", "#18251c"), tiers=4)
    return s


def f_oak():
    s = Svg(72, 80)
    soft_shadow(s, 40, 74, 28, 7)
    s.path("M33,76 L35,52 L39,52 L41,76 Z", s.lin([(0, "#7a5636"), (1, "#3b2817")], 0, 0, 1, 0), stroke="none", sw=0)
    for cx, cy, r, depth in [(48, 34, 17, 0.35), (24, 36, 16, 0.3), (36, 22, 18, 0), (34, 44, 17, 0.1)]:
        fill = s.rad([(0, "#9cb468"), (0.55, "#5f7f3d"), (1, "#2f4526")], 0.36, 0.32, 0.75)
        s.circle(cx, cy, r, fill, stroke="none", sw=0)
        if depth:
            s.circle(cx, cy, r, "#000000", stroke="none", sw=0, opacity=depth * 0.35)
    return s


def mountain_body(s, x, foot, w, h, snowline=0.42):
    soft_shadow(s, x + w * 0.08, foot - 3, w * 0.5, w * 0.11, 0.42)
    top = (x - w * 0.04, foot - h)
    left, right = (x - w / 2, foot), (x + w / 2, foot)
    ridge = (x + w * 0.06, foot - h * 0.25)
    s.poly([left, top, ridge, (x, foot)], s.lin([(0, "#c4bdaf"), (1, "#8c867b")], 0, 0, 0, 1), stroke="none", sw=0)
    s.poly([top, right, (x, foot), ridge], s.lin([(0, "#6f6a61"), (1, "#4a4640")], 0, 0, 1, 1), stroke="none", sw=0)
    for f1, f2 in [(0.3, 0.7), (0.55, 0.45)]:
        a = (top[0] + (left[0] - top[0]) * f1, top[1] + (left[1] - top[1]) * f1)
        s.line(a[0], a[1], a[0] + w * 0.1, a[1] + h * 0.2 * f2, stroke="#5e5a52", sw=1.6, opacity=0.45)
    snow_left = (top[0] + (left[0] - top[0]) * snowline, top[1] + (left[1] - top[1]) * snowline)
    snow_right = (top[0] + (right[0] - top[0]) * snowline * 0.9, top[1] + (right[1] - top[1]) * snowline * 0.9)
    snow_mid = (top[0] + (ridge[0] - top[0]) * snowline * 1.1, top[1] + (ridge[1] - top[1]) * snowline * 1.1)
    s.poly([top, snow_left, (snow_left[0] + w * 0.07, snow_left[1] - h * 0.05), snow_mid], s.lin([(0, "#ffffff"), (1, "#dfe6ea")], 0, 0, 0, 1), stroke="none", sw=0)
    s.poly([top, snow_mid, (snow_mid[0] + w * 0.08, snow_mid[1] - h * 0.03), snow_right], s.lin([(0, "#c7d1d8"), (1, "#a3b0b9")], 0, 0, 1, 1), stroke="none", sw=0)
    # The foot fades into the ground.
    s.rect(left[0], foot - h * 0.16, w, h * 0.16, s.lin([(0, "#7b766c", 0), (1, "#7b766c", 0.85)], 0, 0, 0, 1), stroke="none", sw=0)


def f_mountain():
    s = Svg(160, 128)
    mountain_body(s, 76, 122, 150, 116)
    return s


def f_peak():
    s = Svg(100, 80)
    mountain_body(s, 50, 76, 92, 66, snowline=0.3)
    return s


def f_hill():
    s = Svg(128, 64)
    soft_shadow(s, 70, 56, 56, 8, 0.3)
    s.path("M6,60 Q30,14 64,10 Q100,12 122,60 Z", s.rad([(0, "#b8ae76"), (0.5, "#8f875a"), (1, "#5d583c")], 0.38, 0.3, 0.8), stroke="none", sw=0)
    s.path("M40,30 Q58,18 80,20", "none", stroke="#d6cd94", sw=2.5, opacity=0.35)
    s.rect(0, 46, 128, 18, s.lin([(0, "#8e8657", 0), (1, "#8e8657", 0.9)], 0, 0, 0, 1), stroke="none", sw=0)
    return s


def f_reeds():
    s = Svg(48, 48)
    s.ellipse(24, 42, 18, 4, "#9cc0cc", stroke="none", sw=0, opacity=0.35)
    for x0, lean, h, c in [(14, -6, 30, "#6e7b40"), (20, -2, 36, "#8a9a52"), (26, 3, 34, "#5c6a35"), (32, 7, 28, "#7d8a4a"), (23, 0, 24, "#9aa860")]:
        s.path(f"M{x0},{42} Q{x0 + lean * 0.3},{42 - h * 0.6} {x0 + lean},{42 - h}", "none", stroke=c, sw=2)
    for x0, y0 in [(19, 9), (28, 11)]:
        s.ellipse(x0, y0, 2, 5, "#6b4a2e", stroke="none", sw=0)
    return s


def f_grass():
    s = Svg(40, 28)
    for x0, lean, h, c in [(12, -5, 18, "#7f8f48"), (17, -1, 24, "#a3ad62"), (22, 3, 20, "#8c9a50"), (27, 6, 15, "#b2b56a")]:
        s.path(f"M{x0},26 Q{x0 + lean * 0.3},{26 - h * 0.6} {x0 + lean},{26 - h}", "none", stroke=c, sw=2.2)
    return s


def f_bush():
    s = Svg(44, 32)
    soft_shadow(s, 24, 28, 18, 4, 0.3)
    for cx, cy, r in [(15, 20, 9), (29, 19, 10), (22, 13, 9)]:
        s.circle(cx, cy, r, s.rad([(0, "#97ae63"), (0.6, "#5c7a3c"), (1, "#30462a")], 0.35, 0.3, 0.75), stroke="none", sw=0)
    return s


def f_ice():
    s = Svg(72, 60)
    soft_shadow(s, 38, 54, 28, 5, 0.25)
    s.poly([(10, 54), (22, 18), (34, 30), (40, 54)], s.lin([(0, "#ffffff"), (1, "#c9d8df")], 0, 0, 1, 1), stroke="none", sw=0)
    s.poly([(22, 18), (30, 6), (44, 28), (34, 30)], s.lin([(0, "#f4f8fa"), (1, "#b9cbd4")], 0, 0, 1, 1), stroke="none", sw=0)
    s.poly([(34, 30), (44, 28), (62, 54), (40, 54)], s.lin([(0, "#a8bcc7"), (1, "#7f96a3")], 0, 0, 1, 1), stroke="none", sw=0)
    return s


def f_blossom():
    """Hallowed meadow: pale grass starred with white and gold flowers (low,
    so it never passes for a stone idol or anything else to act on)."""
    s = Svg(48, 32)
    soft_shadow(s, 24, 28, 18, 3, 0.25)
    for x, h in ((10, 14), (18, 18), (26, 15), (34, 19), (40, 12)):
        s.path(f"M{x},28 Q{x - 2},{28 - h * 0.6} {x + 1},{28 - h}", "none", stroke="#8fa45a", sw=2)
    for x, y, c in ((12, 14, "#fbf6ea"), (24, 10, "#f6d572"), (35, 12, "#fbf6ea"), (30, 20, "#fbf6ea"), (18, 21, "#f6d572")):
        s.circle(x, y, 2.6, c, stroke="none", sw=0)
    return s


FEATURES = {
    "pine": f_pine, "dark_pine": f_dark_pine, "oak": f_oak, "mountain": f_mountain, "peak": f_peak,
    "hill": f_hill, "reeds": f_reeds, "grass": f_grass, "bush": f_bush, "ice": f_ice, "blossom": f_blossom,
}


# --- Shaded pieces: three-quarter view, lit from the upper left, no outlines ------

ROOFS = {
    "thatch": ("#d6b46e", "#a8854a", "#6b5229"),
    "red": ("#c9714f", "#9a4733", "#5e281c"),
    "slate": ("#7d8794", "#59626d", "#363d45"),
    "wood": ("#9a6d43", "#6e4b2c", "#432c19"),
}
WALLS = {
    "wood": ("#b78d5e", "#8c6640", "#594027"),
    "plaster": ("#f0e8d5", "#d0c5ae", "#958a76"),
    "stone": ("#c9c3b7", "#9d978c", "#6a655d"),
}
GLOW = "#f3c46a"
EDGE = "#1d1813"


def house(s, x, foot, w, h, roof="thatch", wall="wood", door=True, windows=1):
    """A gabled house facing the viewer, its right side going back."""
    d = w * 0.42
    gable = w * 0.52
    rl, rm, rd = ROOFS[roof]
    wl, wm, wd = WALLS[wall]
    soft_shadow(s, x + d * 0.6, foot - 1, w * 0.62 + d * 0.3, w * 0.16, 0.4)
    # Side wall going back, in shadow.
    s.poly([(x + w / 2, foot), (x + w / 2 + d, foot - d * 0.45), (x + w / 2 + d, foot - h - d * 0.45), (x + w / 2, foot - h)],
           s.lin([(0, wm), (1, wd)], 0, 0, 1, 0), stroke="none", sw=0)
    # Front wall and gable, lit.
    s.poly([(x - w / 2, foot), (x - w / 2, foot - h), (x, foot - h - gable), (x + w / 2, foot - h), (x + w / 2, foot)],
           s.lin([(0, wl), (1, wm)], 0, 0, 1, 0), stroke="none", sw=0)
    # Roof plane over the side, eaves overhanging.
    o = w * 0.06
    s.poly([(x - o * 0.3, foot - h - gable - o), (x + d - o * 0.3, foot - h - gable - d * 0.45 - o),
            (x + w / 2 + d + o, foot - h - d * 0.45 + o), (x + w / 2 + o, foot - h + o)],
           s.lin([(0, rl), (0.55, rm), (1, rd)], 0, 0, 0.3, 1), stroke="none", sw=0)
    # The roof's front edge along the gable.
    s.path(f"M{fmt(x - w / 2 - o)},{fmt(foot - h + o)} L{fmt(x - o * 0.3)},{fmt(foot - h - gable - o)} L{fmt(x + w / 2 + o)},{fmt(foot - h + o)}",
           "none", stroke=rm, sw=max(2.0, w * 0.08))
    if door:
        s.rect(x - w * 0.12, foot - h * 0.62, w * 0.24, h * 0.62, "#3a2a1c", stroke="none", sw=0)
    for i in range(windows):
        wx = x + (w * 0.26 if i == 0 else -w * 0.3)
        s.rect(wx - w * 0.07, foot - h * 0.72, w * 0.14, h * 0.24, GLOW, stroke="none", sw=0, opacity=0.9)
    s.line(x - w / 2, foot, x + w / 2 + d, foot - d * 0.45, stroke=EDGE, sw=1.2, opacity=0.35)


def stakes(s, x0, x1, foot, h, gap=5.0):
    """A palisade of pointed stakes."""
    x = x0
    while x < x1:
        s.poly([(x, foot), (x, foot - h), (x + gap * 0.45, foot - h - gap * 0.7), (x + gap * 0.9, foot - h), (x + gap * 0.9, foot)],
               s.lin([(0, "#a8794a"), (1, "#5b3f25")], 0, 0, 1, 0), stroke="none", sw=0)
        x += gap
    s.rect(x0, foot - h * 0.55, x1 - x0, h * 0.1, "#4a3320", stroke="none", sw=0, opacity=0.7)


def wall(s, x0, x1, foot, h):
    """A crenellated stone wall."""
    s.rect(x0, foot - h, x1 - x0, h, s.lin([(0, "#cfc9bd"), (1, "#8e887d")], 0, 0, 0, 1), stroke="none", sw=0)
    step = 8.0
    x = x0
    while x < x1 - 2:
        s.rect(x, foot - h - 5, step * 0.55, 5, "#c2bcb0", stroke="none", sw=0)
        x += step
    for row in (0.35, 0.7):
        s.line(x0, foot - h * row, x1, foot - h * row, stroke="#6f6a61", sw=1, opacity=0.4)
    s.rect(x0, foot - 3, x1 - x0, 3, "#000000", stroke="none", sw=0, opacity=0.18)


def round_tower(s, x, foot, w, h, roof="red", wall_kind="stone"):
    wl, wm, wd = WALLS[wall_kind]
    rl, rm, rd = ROOFS[roof]
    soft_shadow(s, x + w * 0.3, foot - 1, w * 0.8, w * 0.22, 0.4)
    s.rect(x - w / 2, foot - h, w, h, s.lin([(0, wl), (0.5, wm), (1, wd)], 0, 0, 1, 0), stroke="none", sw=0)
    s.ellipse(x, foot, w / 2, w * 0.14, wd, stroke="none", sw=0)
    s.rect(x - w * 0.08, foot - h * 0.7, w * 0.16, h * 0.18, "#2b211a", stroke="none", sw=0)
    s.poly([(x - w * 0.62, foot - h), (x, foot - h - w * 1.1), (x + w * 0.62, foot - h)], s.lin([(0, rl), (0.5, rm), (1, rd)], 0, 0, 1, 0), stroke="none", sw=0)


def dome(s, x, base, r):
    """A gilded onion dome with a cross."""
    s.path(f"M{fmt(x - r)},{fmt(base)} Q{fmt(x - r * 1.25)},{fmt(base - r * 0.9)} {fmt(x)},{fmt(base - r * 1.9)} "
           f"Q{fmt(x + r * 1.25)},{fmt(base - r * 0.9)} {fmt(x + r)},{fmt(base)} Z",
           s.rad([(0, "#fff3b8"), (0.45, "#e2b33c"), (1, "#8a6212")], 0.35, 0.35, 0.8), stroke="none", sw=0)
    s.line(x, base - r * 1.9, x, base - r * 2.6, stroke="#c99a2e", sw=1.6)
    s.line(x - r * 0.3, base - r * 2.35, x + r * 0.3, base - r * 2.35, stroke="#c99a2e", sw=1.6)


def settlement(tier):
    """Five looks as a village grows (Elder's Hall levels 1-2, 3-4, 5-6, 7-8, 9-10)."""
    s = Svg()
    soft_shadow(s, 66, 114, 56, 12, 0.3)
    if tier == 1:
        house(s, 44, 108, 30, 18)
        house(s, 82, 112, 24, 15)
        s.circle(64, 116, 3, GLOW, stroke="none", sw=0)
    elif tier == 2:
        house(s, 64, 92, 28, 17)
        house(s, 38, 104, 30, 18)
        house(s, 88, 108, 26, 16)
        stakes(s, 12, 116, 122, 10)
    elif tier == 3:
        house(s, 30, 96, 24, 15)
        house(s, 98, 98, 22, 14)
        house(s, 64, 98, 40, 24, roof="red", wall="wood", windows=2)
        stakes(s, 8, 120, 122, 14)
    elif tier == 4:
        round_tower(s, 16, 114, 14, 40, roof="wood", wall_kind="wood")
        round_tower(s, 112, 114, 14, 40, roof="wood", wall_kind="wood")
        house(s, 36, 98, 24, 15)
        house(s, 70, 96, 46, 26, roof="red", wall="plaster", windows=2)
        stakes(s, 8, 120, 122, 16)
    else:
        house(s, 34, 96, 26, 16, roof="red", wall="plaster")
        house(s, 94, 96, 26, 16, roof="red", wall="plaster")
        house(s, 64, 92, 44, 30, roof="slate", wall="plaster", windows=2)
        dome(s, 66, 44, 8)
        wall(s, 10, 118, 122, 16)
        round_tower(s, 12, 122, 16, 44)
        round_tower(s, 116, 122, 16, 44)
    return s


def ruins():
    s = Svg()
    soft_shadow(s, 64, 112, 52, 11, 0.35)
    s.poly([(26, 112), (26, 82), (34, 74), (40, 86), (40, 112)], s.lin([(0, "#6b5a48"), (1, "#3a3027")], 0, 0, 1, 0), stroke="none", sw=0)
    s.poly([(70, 112), (70, 90), (80, 80), (88, 96), (98, 90), (98, 112)], s.lin([(0, "#9d978c"), (1, "#5d5850")], 0, 0, 1, 0), stroke="none", sw=0)
    s.poly([(42, 112), (60, 96), (66, 100), (50, 114)], "#4a3a2c", stroke="none", sw=0)
    for x, y, r, o in [(52, 64, 11, 0.45), (60, 46, 14, 0.35), (70, 26, 17, 0.25)]:
        s.circle(x, y, r, s.rad([(0, "#4d4842", o), (1, "#4d4842", 0)]), stroke="none", sw=0)
    s.circle(54, 106, 4, "#e8642c", stroke="none", sw=0, opacity=0.8)
    return s


def holy_city():
    s = Svg(160, 160)
    soft_shadow(s, 82, 146, 74, 14, 0.35)
    house(s, 80, 104, 64, 34, roof="slate", wall="plaster", windows=2)
    for x, r in [(56, 9), (104, 9)]:
        s.rect(x - 7, 70, 14, 22, s.lin([(0, "#f5efe1"), (1, "#bfb6a1")], 0, 0, 1, 0), stroke="none", sw=0)
        dome(s, x, 72, r)
    s.rect(70, 46, 24, 30, s.lin([(0, "#f5efe1"), (1, "#bfb6a1")], 0, 0, 1, 0), stroke="none", sw=0)
    dome(s, 82, 48, 14)
    wall(s, 14, 148, 146, 20)
    round_tower(s, 16, 146, 20, 52, roof="red")
    round_tower(s, 146, 146, 20, 52, roof="red")
    s.path("M70,146 L70,132 Q80,120 90,132 L90,146 Z", "#3a2a1c", stroke="none", sw=0)
    return s


def tent(s, x, foot, w, color=("#c9a77a", "#8c6a45", "#5a4129")):
    light, mid, dark = color
    soft_shadow(s, x + w * 0.2, foot - 1, w * 0.62, w * 0.16, 0.35)
    s.poly([(x - w / 2, foot), (x, foot - w * 0.8), (x + w * 0.1, foot)], s.lin([(0, light), (1, mid)], 0, 0, 1, 0), stroke="none", sw=0)
    s.poly([(x + w * 0.1, foot), (x, foot - w * 0.8), (x + w / 2 + w * 0.15, foot - w * 0.05)], s.lin([(0, mid), (1, dark)], 0, 0, 1, 0), stroke="none", sw=0)
    s.poly([(x - w * 0.12, foot), (x, foot - w * 0.4), (x + w * 0.06, foot)], "#2b211a", stroke="none", sw=0)


def camp(kind):
    s = Svg()
    if kind == "bandit":
        soft_shadow(s, 64, 112, 50, 11, 0.3)
        tent(s, 42, 104, 40, ("#b98a5e", "#8a5e3c", "#563821"))
        tent(s, 86, 110, 34, ("#a8414b", "#7c2c34", "#4c1a20"))
        s.circle(64, 114, 7, s.rad([(0, "#ffd27a", 0.95), (0.5, "#e8642c", 0.8), (1, "#e8642c", 0)]), stroke="none", sw=0)
        s.line(98, 112, 98, 70, stroke="#5b3f25", sw=2.5)
        s.poly([(98, 70), (116, 76), (98, 82)], "#a83a2c", stroke="none", sw=0)
    else:
        soft_shadow(s, 64, 114, 56, 12, 0.35)
        s.path("M10,116 Q22,52 64,40 Q106,52 118,116 Z", s.rad([(0, "#8e8a7f"), (0.6, "#5f5b53"), (1, "#3a3732")], 0.35, 0.3, 0.8), stroke="none", sw=0)
        s.path("M40,116 Q44,76 64,70 Q84,76 88,116 Z", s.rad([(0, "#0d0b0a"), (1, "#26221e")], 0.5, 0.8, 0.7), stroke="none", sw=0)
        for x in (56, 72):
            s.circle(x, 94, 3, s.rad([(0, "#fff3a0"), (1, "#ff9a2e", 0)]), stroke="none", sw=0)
        s.path("M18,112 Q30,104 40,108", "none", stroke="#d8d2c4", sw=3, opacity=0.6)
    return s


def fort():
    s = Svg()
    soft_shadow(s, 64, 114, 54, 12, 0.35)
    stakes(s, 14, 114, 118, 18, gap=6)
    round_tower(s, 64, 102, 22, 52, roof="wood", wall_kind="wood")
    s.line(64, 42, 64, 26, stroke="#5b3f25", sw=2)
    s.poly([(64, 26), (80, 31), (64, 36)], "#a83a2c", stroke="none", sw=0)
    return s


def outpost():
    s = Svg()
    house(s, 58, 108, 34, 20, roof="wood", wall="wood")
    for i, x in enumerate((86, 94, 102)):
        s.circle(x, 112 - (i % 2) * 6, 5, s.rad([(0, "#c49a6c"), (1, "#6b4a2c")]), stroke="none", sw=0)
    return s


def site(kind):
    s = Svg()
    soft_shadow(s, 64, 112, 52, 11, 0.3)
    if kind == "kurgan":
        s.path("M12,114 Q30,56 64,52 Q98,56 116,114 Z", s.rad([(0, "#a5b06a"), (0.6, "#76824a"), (1, "#4a5531")], 0.38, 0.3, 0.8), stroke="none", sw=0)
        for x, h in [(48, 18), (64, 24), (80, 18)]:
            s.poly([(x - 4, 60), (x - 3, 60 - h), (x + 3, 60 - h + 2), (x + 4, 60)], s.lin([(0, "#bdb6aa"), (1, "#6f695f")], 0, 0, 1, 0), stroke="none", sw=0)
    elif kind == "sunken_shrine":
        s.ellipse(64, 104, 52, 16, s.rad([(0, "#6aa0b4"), (1, "#2d5a6c")]), stroke="none", sw=0)
        s.poly([(50, 104), (50, 60), (78, 60), (78, 104)], s.lin([(0, "#b5ae9f"), (1, "#6f695e")], 0, 0, 1, 0), stroke="none", sw=0)
        s.poly([(44, 62), (64, 44), (84, 62)], s.lin([(0, "#8c8578"), (1, "#4f4a42")], 0, 0, 1, 0), stroke="none", sw=0)
        s.path("M24,104 Q40,98 56,104 M72,106 Q88,100 104,106", "none", stroke="#c8e0e8", sw=2, opacity=0.6)
    elif kind == "old_hillfort":
        s.ellipse(64, 96, 54, 24, s.rad([(0, "#9aa463"), (1, "#5b6638")]), stroke="none", sw=0)
        s.ellipse(64, 92, 38, 15, "none", stroke="#4d5730", sw=6, opacity=0.8)
        s.ellipse(64, 90, 38, 15, "none", stroke="#b2bb78", sw=2.5, opacity=0.6)
        stakes(s, 46, 82, 92, 10, gap=6)
    elif kind == "stone_idol":
        s.path("M48,116 L50,46 Q64,30 78,46 L80,116 Z", s.lin([(0, "#c4bdb0"), (0.55, "#8e877b"), (1, "#5a554d")], 0, 0, 1, 0), stroke="none", sw=0)
        for y in (58, 78, 98):
            s.line(52, y, 76, y, stroke="#4f4a43", sw=2, opacity=0.6)
            s.circle(58, y - 7, 2, "#3a3631", stroke="none", sw=0)
            s.circle(70, y - 7, 2, "#3a3631", stroke="none", sw=0)
    else:  # frozen_ruin
        s.poly([(14, 116), (34, 70), (56, 116)], s.lin([(0, "#ffffff"), (1, "#b9cbd4")], 0, 0, 1, 1), stroke="none", sw=0)
        for x in (60, 80, 100):
            s.rect(x - 5, 66, 10, 50, s.lin([(0, "#dfe7eb"), (1, "#8fa4b0")], 0, 0, 1, 0), stroke="none", sw=0)
        s.rect(54, 60, 52, 8, s.lin([(0, "#eef3f5"), (1, "#a9bcc6")], 0, 0, 0, 1), stroke="none", sw=0)
    return s


def resource(kind):
    s = Svg()
    if kind == "wood":
        soft_shadow(s, 64, 106, 46, 9, 0.35)
        for x, y in [(42, 94), (86, 94), (64, 70)]:
            s.rect(x - 26, y - 13, 52, 26, s.lin([(0, "#c08a55"), (0.5, "#8a5b31"), (1, "#5a3a1f")], 0, 0, 0, 1), stroke="none", sw=0, rx=12)
            s.circle(x + 18, y, 11, s.rad([(0, "#e7c38f"), (0.7, "#c9975e"), (1, "#8a5b31")]), stroke="none", sw=0)
            for r in (7, 3.5):
                s.circle(x + 18, y, r, "none", stroke="#8a5b31", sw=1.2, opacity=0.6)
    elif kind == "stone":
        soft_shadow(s, 64, 108, 46, 9, 0.35)
        s.poly([(20, 106), (30, 72), (58, 62), (72, 86), (64, 106)], s.lin([(0, "#cfc9bd"), (1, "#7d776d")], 0, 0, 1, 1), stroke="none", sw=0)
        s.poly([(58, 106), (68, 56), (98, 46), (110, 82), (102, 106)], s.lin([(0, "#e1dbd0"), (1, "#8c867b")], 0, 0, 1, 1), stroke="none", sw=0)
        s.poly([(68, 56), (98, 46), (92, 60), (72, 66)], "#f4f0e8", stroke="none", sw=0, opacity=0.6)
    elif kind == "grain":
        soft_shadow(s, 64, 110, 34, 8, 0.35)
        for dx in (-16, -6, 6, 16):
            s.line(64, 108, 64 + dx * 1.7, 34, stroke="#b48d3e", sw=4)
            s.ellipse(64 + dx * 1.7, 36, 7, 15, s.rad([(0, "#f6dc8a"), (0.7, "#d9b14f"), (1, "#9c7a2a")], 0.35, 0.3, 0.8), stroke="none", sw=0)
        s.rect(44, 78, 40, 9, s.lin([(0, "#c9614a"), (1, "#7c2c22")], 0, 0, 0, 1), stroke="none", sw=0, rx=3)
    elif kind == "iron":
        soft_shadow(s, 64, 104, 46, 9, 0.35)
        for y, x0 in [(98, 22), (76, 34)]:
            s.poly([(x0, y), (x0 + 12, y - 22), (x0 + 72, y - 22), (x0 + 84, y)], s.lin([(0, "#a9b4c2"), (0.5, "#6c7684"), (1, "#3c434d")], 0, 0, 0, 1), stroke="none", sw=0)
            s.poly([(x0 + 14, y - 20), (x0 + 70, y - 20), (x0 + 66, y - 14), (x0 + 18, y - 14)], "#d8e0ea", stroke="none", sw=0, opacity=0.55)
    elif kind == "ember":
        s.circle(64, 72, 42, s.rad([(0, "#ffd88a", 0.5), (1, "#e8642c", 0)]), stroke="none", sw=0)
        s.path("M64,32 Q92,62 80,92 Q64,106 48,92 Q36,62 64,32 Z", s.rad([(0, "#fff1b0"), (0.4, "#ffb347"), (1, "#c2410c")], 0.5, 0.7, 0.7), stroke="none", sw=0)
        s.path("M64,58 Q76,76 70,90 Q64,94 58,90 Q52,76 64,58 Z", "#fff6d6", stroke="none", sw=0, opacity=0.8)
    return s

def enamel(s, rim=("#f3d98f", "#b48a2e", "#7a5a17")):
    """A dark enamel medallion in a gold rim."""
    soft_shadow(s, 66, 116, 46, 8, 0.35)
    s.circle(64, 62, 54, s.lin([(0, rim[0]), (0.5, rim[1]), (1, rim[2])], 0, 0, 1, 1), stroke="none", sw=0)
    s.circle(64, 62, 47, s.rad([(0, "#3a4452"), (0.7, "#1d232c"), (1, "#11151a")], 0.4, 0.3, 0.8), stroke="none", sw=0)
    s.circle(64, 62, 47, "none", stroke="#000000", sw=1.5, opacity=0.5)
    return s.lin([(0, "#fbf5e6"), (1, "#bdb29b")], 0, 0, 1, 1)


def unit(kind):
    s = Svg()
    pale = enamel(s)
    if kind in ("spearman",):
        s.line(42, 96, 86, 26, stroke=pale, sw=5)
        s.poly([(86, 26), (92, 16), (90, 32)], pale, stroke="none", sw=0)
        s.circle(54, 70, 18, s.rad([(0, "#c9614a"), (1, "#6e2a1f")], 0.35, 0.3, 0.8), stroke="none", sw=0)
        s.circle(54, 70, 18, "none", stroke=pale, sw=3)
        s.circle(54, 70, 4, pale, stroke="none", sw=0)
    elif kind in ("archer", "forest_archer"):
        s.path("M48,22 Q86,62 48,102", "none", stroke=pale, sw=5)
        s.line(48, 22, 48, 102, stroke="#d9cfb8", sw=1.5)
        s.line(40, 62, 96, 62, stroke=pale, sw=3.5)
        s.poly([(96, 62), (86, 56), (86, 68)], pale, stroke="none", sw=0)
        if kind == "forest_archer":
            s.path("M86,30 Q100,22 102,36 Q90,42 86,30 Z", s.lin([(0, "#9cbf6a"), (1, "#4f7a34")]), stroke="none", sw=0)
    elif kind in ("horseman", "border_rider"):
        s.path("M44,100 L48,70 Q46,48 58,32 L66,22 L70,34 Q86,40 90,56 L84,62 L70,56 Q68,72 76,100 Z", pale, stroke="none", sw=0)
        s.circle(70, 42, 2.5, "#1d232c", stroke="none", sw=0)
        if kind == "border_rider":
            s.line(90, 98, 90, 24, stroke="#d9cfb8", sw=2.5)
            s.poly([(90, 24), (106, 30), (90, 36)], "#c9614a", stroke="none", sw=0)
    elif kind == "scout":
        s.path("M24,62 Q64,28 104,62 Q64,96 24,62 Z", pale, stroke="none", sw=0)
        s.circle(64, 62, 14, s.rad([(0, "#7fb6cf"), (1, "#2b5a70")]), stroke="none", sw=0)
        s.circle(64, 62, 6, "#11151a", stroke="none", sw=0)
        s.circle(60, 58, 2.5, "#ffffff", stroke="none", sw=0)
    elif kind == "settler":
        s.path("M28,74 Q64,30 100,74 Z", pale, stroke="none", sw=0)
        s.rect(26, 74, 76, 12, s.lin([(0, "#b78d5e"), (1, "#594027")], 0, 0, 0, 1), stroke="none", sw=0, rx=2)
        for x in (40, 88):
            s.circle(x, 92, 9, s.rad([(0, "#c9a16e"), (1, "#5a3a1f")]), stroke="none", sw=0)
            s.circle(x, 92, 3, "#1d232c", stroke="none", sw=0)
    elif kind == "river_barge":
        s.path("M24,74 L104,74 L92,92 L36,92 Z", s.lin([(0, "#b78d5e"), (1, "#594027")], 0, 0, 0, 1), stroke="none", sw=0)
        s.line(62, 74, 62, 24, stroke=pale, sw=4)
        s.poly([(66, 26), (92, 68), (66, 68)], pale, stroke="none", sw=0)
        s.path("M28,100 Q38,94 48,100 Q58,106 68,100 Q78,94 88,100", "none", stroke="#7fb6cf", sw=3)
    return s


# The enemy's units: the same enamel medallion in an iron rim run with
# madder, so a glance tells theirs from ours (gold). Kinds that share a
# shape share its drawing.
ENEMY_UNITS = {
    "north": ["grey_wolf", "leshy_thrall", "cave_bear", "volkolak", "upyr", "likho", "zmey_whelp"],
    "east": ["steppe_raider", "horse_archer", "lancer", "shaman", "khans_guard", "scaling_ladders"],
    "order": ["zealot", "crossbowman", "knight_brother", "inquisitor", "siege_ram", "catapult", "siege_tower"],
}
ENEMY_RIM = ("#d98a7a", "#8e2f26", "#3e1410")


def horse_head(s, pale):
    s.path("M44,100 L48,70 Q46,48 58,32 L66,22 L70,34 Q86,40 90,56 L84,62 L70,56 Q68,72 76,100 Z", pale, stroke="none", sw=0)
    s.circle(70, 42, 2.5, "#1d232c", stroke="none", sw=0)


def wolf_head(s, pale):
    s.path("M30,86 L44,64 L40,30 L56,48 Q64,44 72,48 L88,30 L84,64 L100,86 L74,80 L64,96 L54,80 Z", pale, stroke="none", sw=0)
    for x in (54, 74):
        s.poly([(x - 5, 62), (x + 5, 62), (x, 66)], "#c9614a", stroke="none", sw=0)


def enemy(kind):
    s = Svg()
    pale = enamel(s, ENEMY_RIM)
    red = s.lin([(0, "#e07a62"), (1, "#8e2f26")], 0, 0, 1, 1)
    if kind in ("grey_wolf", "volkolak"):
        wolf_head(s, pale)
        if kind == "volkolak":
            s.path("M64,18 A9,9 0 1,0 64,36 A12,12 0 0,1 64,18 Z", "#e6dcc2", stroke="none", sw=0)
    elif kind == "cave_bear":
        s.circle(64, 66, 28, pale, stroke="none", sw=0)
        for x in (42, 86):
            s.circle(x, 42, 10, pale, stroke="none", sw=0)
        s.ellipse(64, 78, 11, 8, "#bdb29b", stroke="none", sw=0)
        s.circle(64, 74, 4, "#1d232c", stroke="none", sw=0)
        for x in (54, 74):
            s.circle(x, 60, 3, "#1d232c", stroke="none", sw=0)
    elif kind == "leshy_thrall":
        s.path("M50,100 Q48,70 64,56 Q80,70 78,100 Z", pale, stroke="none", sw=0)
        for side in (-1, 1):
            s.path(f"M{64 + side * 6},56 Q{64 + side * 22},40 {64 + side * 30},22 M{64 + side * 18},44 Q{64 + side * 30},42 {64 + side * 38},34", "none", stroke=pale, sw=4)
        for x in (58, 70):
            s.circle(x, 72, 3, "#9cbf6a", stroke="none", sw=0)
    elif kind == "upyr":
        s.path("M18,58 Q40,40 64,54 Q88,40 110,58 L98,62 L92,74 L80,66 L64,84 L48,66 L36,74 L30,62 Z", pale, stroke="none", sw=0)
        for x in (58, 70):
            s.poly([(x - 3, 84), (x + 3, 84), (x, 96)], pale, stroke="none", sw=0)
    elif kind == "likho":
        # One-eyed Likho: a single great eye.
        s.path("M20,62 Q64,22 108,62 Q64,102 20,62 Z", pale, stroke="none", sw=0)
        s.circle(64, 62, 18, red, stroke="none", sw=0)
        s.circle(64, 62, 8, "#11151a", stroke="none", sw=0)
        s.circle(59, 57, 3, "#ffffff", stroke="none", sw=0)
    elif kind == "zmey_whelp":
        s.path("M28,92 Q36,56 64,46 L80,30 L84,44 Q100,48 104,62 L90,66 Q78,64 72,72 Q60,84 64,100 Z", pale, stroke="none", sw=0)
        s.circle(86, 52, 2.5, "#1d232c", stroke="none", sw=0)
        s.path("M104,62 Q112,66 108,74 Q100,70 98,66 Z", s.lin([(0, "#ffd27a"), (1, "#e8642c")]), stroke="none", sw=0)
    elif kind == "steppe_raider":
        s.path("M34,96 Q50,52 96,26 Q66,58 44,100 Z", pale, stroke="none", sw=0)
        s.line(34, 96, 46, 104, stroke="#c9a16e", sw=5)
    elif kind == "horse_archer":
        horse_head(s, pale)
        s.path("M92,28 Q72,62 92,96", "none", stroke="#e6dcc2", sw=4)
    elif kind == "lancer":
        horse_head(s, pale)
        s.line(98, 100, 98, 20, stroke="#e6dcc2", sw=3)
        s.poly([(98, 20), (112, 26), (98, 32)], red, stroke="none", sw=0)
    elif kind == "shaman":
        s.circle(64, 62, 30, pale, stroke="none", sw=0)
        s.circle(64, 62, 22, "none", stroke="#8e2f26", sw=2.5)
        s.path("M64,44 L64,80 M48,62 L80,62 M54,50 L74,74 M74,50 L54,74", "none", stroke="#8e2f26", sw=2.5)
    elif kind == "khans_guard":
        s.path("M40,90 Q40,58 64,44 Q88,58 88,90 Z", pale, stroke="none", sw=0)
        s.line(64, 44, 64, 22, stroke=pale, sw=4)
        s.path("M64,22 Q80,26 84,40 Q72,32 64,30 Z", red, stroke="none", sw=0)
        s.rect(40, 88, 48, 8, "#bdb29b", stroke="none", sw=0, rx=2)
    elif kind == "zealot":
        s.path("M40,30 L88,30 L88,64 Q88,92 64,104 Q40,92 40,64 Z", pale, stroke="none", sw=0)
        s.path("M50,64 L54,46 L60,56 L64,42 L68,56 L74,46 L78,64 Z", "#b48a2e", stroke="none", sw=0)
    elif kind == "crossbowman":
        s.line(64, 28, 64, 100, stroke=pale, sw=6)
        s.path("M30,52 Q64,36 98,52", "none", stroke=pale, sw=5)
        s.line(30, 52, 64, 72, stroke="#d9cfb8", sw=1.5)
        s.line(98, 52, 64, 72, stroke="#d9cfb8", sw=1.5)
    elif kind == "knight_brother":
        horse_head(s, pale)
        s.path("M56,32 L60,18 L66,28 L72,16 L76,30 Z", "#b48a2e", stroke="none", sw=0)
    elif kind == "inquisitor":
        s.rect(58, 60, 12, 42, pale, stroke="none", sw=0, rx=3)
        s.path("M64,20 Q84,40 74,58 L54,58 Q44,40 64,20 Z", s.lin([(0, "#ffd27a"), (0.6, "#e8642c"), (1, "#8e2f26")]), stroke="none", sw=0)
    elif kind == "siege_ram":
        s.path("M24,64 L64,36 L104,64 Z", pale, stroke="none", sw=0)
        s.rect(20, 66, 88, 12, s.lin([(0, "#b78d5e"), (1, "#594027")], 0, 0, 0, 1), stroke="none", sw=0, rx=4)
        s.circle(20, 72, 8, "#8d98a6", stroke="none", sw=0)
        for x in (38, 90):
            s.circle(x, 90, 9, s.rad([(0, "#c9a16e"), (1, "#5a3a1f")]), stroke="none", sw=0)
    elif kind == "catapult":
        s.rect(26, 84, 76, 10, s.lin([(0, "#b78d5e"), (1, "#594027")], 0, 0, 0, 1), stroke="none", sw=0, rx=2)
        s.line(44, 86, 92, 32, stroke=pale, sw=6)
        s.circle(92, 32, 9, "none", stroke=pale, sw=4)
        s.line(56, 86, 64, 60, stroke="#d9cfb8", sw=4)
    elif kind == "siege_tower":
        s.path("M42,104 L48,28 L80,28 L86,104 Z", pale, stroke="none", sw=0)
        for y in (48, 68, 88):
            s.line(46, y, 82, y, stroke="#8e2f26", sw=2)
        s.path("M80,30 L104,48 L100,52 L80,38 Z", "#bdb29b", stroke="none", sw=0)
    elif kind == "scaling_ladders":
        s.line(44, 104, 70, 22, stroke=pale, sw=5)
        s.line(64, 104, 90, 22, stroke=pale, sw=5)
        for i in range(6):
            t = (i + 0.6) / 6.4
            s.line(44 + 26 * t, 104 - 82 * t, 64 + 26 * t, 104 - 82 * t, stroke=pale, sw=3.5)
    return s


def faction(front):
    """A horde's heraldic shield: its colour and its sign."""
    s = Svg()
    field = {
        "north": ("#3d5a49", "#1f3328"),
        "east": ("#b07a32", "#5e3c12"),
        "order": ("#8c2a2f", "#43121a"),
    }[front]
    soft_shadow(s, 66, 120, 40, 7, 0.35)
    shield = "M24,14 L104,14 L104,58 Q104,98 64,118 Q24,98 24,58 Z"
    s.path(shield, s.lin([(0, "#f3d98f"), (0.5, "#b48a2e"), (1, "#7a5a17")], 0, 0, 1, 1), stroke="none", sw=0)
    s.path("M30,20 L98,20 L98,58 Q98,94 64,111 Q30,94 30,58 Z", s.rad([(0, field[0]), (1, field[1])], 0.4, 0.3, 0.9), stroke="none", sw=0)
    pale = s.lin([(0, "#fbf5e6"), (1, "#c9bea6")], 0, 0, 1, 1)
    if front == "north":
        for dx in (-16, 0, 16):
            s.path(f"M{64 + dx - 4},{34} Q{64 + dx + 8},{64} {64 + dx - 2},{96} Q{64 + dx + 2},{64} {64 + dx - 4},{34} Z", pale, stroke="none", sw=0)
    elif front == "east":
        s.path("M78,34 A28,28 0 1,0 78,90 A22,22 0 1,1 78,34 Z", pale, stroke="none", sw=0)
        s.path("M80,52 L84,62 L94,62 L86,68 L89,78 L80,72 L71,78 L74,68 L66,62 L76,62 Z", pale, stroke="none", sw=0)
    else:
        s.path("M40,82 L44,52 L54,66 L64,44 L74,66 L84,52 L88,82 Z", s.lin([(0, "#fff3b8"), (0.5, "#e2b33c"), (1, "#8a6212")], 0, 0, 1, 1), stroke="none", sw=0)
        s.rect(40, 82, 48, 8, "#c99a2e", stroke="none", sw=0)
    return s

# --- Village interior: buildings and fields in three stages --------------------
# Stage 1: levels 1-3, stage 2: 4-7, stage 3: 8 and up (client Art.building_id).

VILLAGE_BUILDINGS = ["elder_hall", "storehouse", "barracks", "scout_lodge", "caravan_yard", "settlers_lodge", "academy", "granary_temple", "stone_redoubt", "longhouse_hall"]
FIELDS = ["woodcutter", "quarry", "farm", "iron_mine"]
WALL_TOWERS = ["archer_tower", "gate_tower", "ballista", "murder_holes", "ditch", "watchtower"]


def plot_ground(s, color=("#a08f6a", "#7a6a4b")):
    s.ellipse(64, 104, 58, 19, s.rad([(0, color[0], 0.9), (0.75, color[1], 0.7), (1, color[1], 0)]), stroke="none", sw=0)


def sign(s, x, y, emblem):
    """A small painted board hung on a building: its trade."""
    s.rect(x - 11, y - 11, 22, 22, s.lin([(0, "#c9614a"), (1, "#6e2a1f")], 0, 0, 1, 1), stroke="none", sw=0, rx=3)
    pale = "#f4ead2"
    if emblem == "spears":
        s.line(x - 7, y + 7, x + 7, y - 7, stroke=pale, sw=2.5)
        s.line(x + 7, y + 7, x - 7, y - 7, stroke=pale, sw=2.5)
    elif emblem == "scroll":
        s.rect(x - 7, y - 5, 14, 10, pale, stroke="none", sw=0, rx=2)
    elif emblem == "sheaf":
        for dx in (-5, 0, 5):
            s.line(x, y + 7, x + dx, y - 6, stroke="#f2cf72", sw=2.5)


def cart(s, x, foot, w=34, covered=False):
    soft_shadow(s, x + 2, foot, w * 0.6, 4, 0.3)
    if covered:
        s.path(f"M{fmt(x - w / 2)},{fmt(foot - 10)} Q{fmt(x)},{fmt(foot - 36)} {fmt(x + w / 2)},{fmt(foot - 10)} Z",
               s.lin([(0, "#f4eddc"), (1, "#b9ae96")], 0, 0, 1, 0), stroke="none", sw=0)
    s.rect(x - w / 2, foot - 12, w, 9, s.lin([(0, "#b78d5e"), (1, "#594027")], 0, 0, 0, 1), stroke="none", sw=0, rx=2)
    for dx in (-w / 3, w / 3):
        s.circle(x + dx, foot - 2, 5.5, s.rad([(0, "#c9a16e"), (1, "#5a3a1f")]), stroke="none", sw=0)


def barrel(s, x, foot, r=7):
    s.rect(x - r, foot - r * 2, r * 2, r * 2, s.lin([(0, "#c49a6c"), (0.5, "#8a6440"), (1, "#4f3822")], 0, 0, 1, 0), stroke="none", sw=0, rx=r * 0.4)
    for y in (foot - r * 1.5, foot - r * 0.5):
        s.line(x - r, y, x + r, y, stroke="#3a2a1c", sw=1.4, opacity=0.6)


def banner_pole(s, x, foot, h, color="#a83a2c"):
    s.line(x, foot, x, foot - h, stroke="#5b3f25", sw=2.5)
    s.path(f"M{x},{foot - h} L{x + 18},{foot - h + 4} L{x + 14},{foot - h + 10} L{x + 18},{foot - h + 16} L{x},{foot - h + 14} Z",
           s.lin([(0, color), (1, "#4c1a20")], 0, 0, 1, 0), stroke="none", sw=0)


def building(kind, stage):
    s = Svg()
    plot_ground(s)
    big = [0, 0.82, 0.95, 1.08][stage]
    if kind == "elder_hall":
        wall_kind = ["", "wood", "plaster", "stone"][stage]
        house(s, 58, 110, 64 * big, 34 * big, roof="red" if stage < 3 else "slate", wall=wall_kind, windows=2)
        if stage >= 2:
            banner_pole(s, 104, 108, 58)
        if stage == 3:
            dome(s, 60, 52, 8)
    elif kind == "storehouse":
        house(s, 56, 110, 58 * big, 30 * big, roof="thatch" if stage < 3 else "red", wall="wood", windows=0)
        for i in range(stage):
            barrel(s, 18 + i * 13, 112)
    elif kind == "barracks":
        if stage == 1:
            tent(s, 40, 108, 40)
            tent(s, 84, 110, 36, ("#b98a5e", "#8a5e3c", "#563821"))
        else:
            house(s, 56, 110, 66 * big, 30 * big, roof="slate", wall="wood" if stage == 2 else "stone", windows=2)
            if stage == 3:
                round_tower(s, 108, 112, 16, 50)
        sign(s, 30 if stage > 1 else 64, 70 if stage > 1 else 58, "spears")
    elif kind == "scout_lodge":
        h = [0, 34, 46, 56][stage]
        soft_shadow(s, 66, 112, 26, 6, 0.35)
        for x0, x1 in ((48, 56), (80, 72)):
            s.line(x0, 112, x1, 112 - h, stroke=s.lin([(0, "#a8794a"), (1, "#5b3f25")], 0, 0, 1, 0), sw=6)
        s.line(52, 112 - h * 0.4, 76, 112 - h * 0.62, stroke="#6e4b2c", sw=3)
        house(s, 64, 112 - h, 32, 12, roof="thatch", wall="wood", door=False)
        if stage == 3:
            banner_pole(s, 64, 112 - h - 26, 22)
    elif kind == "caravan_yard":
        house(s, 40, 108, 46 * big, 24 * big, roof="thatch", wall="wood", windows=0)
        for i in range(stage):
            cart(s, 94, 114 - i * 14, covered=i == stage - 1)
    elif kind == "settlers_lodge":
        house(s, 44, 110, 44 * big, 24 * big, roof="thatch", wall="wood")
        cart(s, 94, 112, covered=True)
        if stage == 3:
            house(s, 98, 86, 22, 12, roof="thatch", wall="wood", door=False)
    elif kind == "academy":
        house(s, 58, 110, 62 * big, 34 * big, roof="red", wall="plaster", windows=2)
        sign(s, 26, 88, "scroll")
        if stage == 3:
            s.path("M50,54 Q62,30 74,54 Z", s.rad([(0, "#bfe3ef"), (0.5, "#4f8fb0"), (1, "#24485c")], 0.35, 0.3, 0.8), stroke="none", sw=0)
    elif kind == "granary_temple":
        s.rect(20, 100, 78, 12, s.lin([(0, "#c9c3b7"), (1, "#8a847a")], 0, 0, 0, 1), stroke="none", sw=0)
        house(s, 56, 100, 54 * big, 26 * big, roof="thatch", wall="wood", windows=0)
        sign(s, 26, 82, "sheaf")
        if stage >= 2:
            dome(s, 58, 52 - stage * 3, 6 + stage)
    elif kind == "stone_redoubt":
        w = 76 * big
        soft_shadow(s, 66, 112, w * 0.6, 10, 0.35)
        wall(s, 64 - w / 2, 64 + w / 2, 112, 34)
        s.path("M54,112 L54,94 Q64,84 74,94 L74,112 Z", "#2b211a", stroke="none", sw=0)
        if stage >= 2:
            round_tower(s, 64 - w / 2, 114, 18, 52)
        if stage == 3:
            round_tower(s, 64 + w / 2, 114, 18, 52)
    elif kind == "longhouse_hall":
        house(s, 52, 110, 76 * big, 22 * big, roof="thatch", wall="wood", windows=2)
        for i in range(stage):
            s.circle(26 + i * 12, 112, 3.5, GLOW, stroke="none", sw=0)
    return s


def wall_gate(material):
    """The walls' plot: their gate, in the walls' material (data/walls.json
    tiers): a palisade of sharpened logs, a timber rampart on an earth bank,
    a stone wall, fortress walls."""
    s = Svg()
    plot_ground(s, ("#9a8a68", "#6e5f45"))
    if material == "wood":
        stakes(s, 14, 50, 108, 26, gap=6)
        stakes(s, 78, 114, 108, 26, gap=6)
        s.rect(50, 74, 28, 34, s.lin([(0, "#a8794a"), (1, "#5b3f25")], 0, 0, 1, 0), stroke="none", sw=0)
        s.line(50, 90, 78, 90, stroke="#3a2a1c", sw=2.5)
    elif material == "timber":
        # The earth bank, lit from the upper left, and the breastwork on it.
        s.path("M8,112 Q14,92 30,90 L98,90 Q114,92 120,112 Z", s.lin([(0, "#a88f62"), (1, "#5e4a2e")], 0, 0, 0.4, 1), stroke="none", sw=0)
        for x0, x1 in ((16, 50), (78, 112)):
            for i, x in enumerate(range(x0, x1, 7)):
                s.rect(x, 66 + (i % 2) * 2, 6.5, 26, s.lin([(0, "#b8875a"), (1, "#5b3f25")], 0, 0, 1, 0), stroke="none", sw=0, rx=2)
            s.line(x0, 74, x1, 74, stroke="#4a3320", sw=2)
        # A timber gatehouse with a plank roof.
        s.rect(48, 56, 32, 54, s.lin([(0, "#c08f60"), (1, "#5b3f25")], 0, 0, 1, 0), stroke="none", sw=0)
        s.path("M44,58 L64,42 L84,58 Z", s.lin([(0, "#8c5a32"), (1, "#4a2e18")], 0, 0, 1, 1), stroke="none", sw=0)
        s.path("M54,110 L54,84 Q64,76 74,84 L74,110 Z", "#2b211a", stroke="none", sw=0)
    else:
        fortress = material == "fortress"
        wall(s, 12, 116, 110, 38 if fortress else 30)
        s.path("M50,110 L50,84 Q64,70 78,84 L78,110 Z", "#2b211a", stroke="none", sw=0)
        for x in (44, 84):
            round_tower(s, x, 112, 20 if fortress else 16, 62 if fortress else 50, roof="slate" if fortress else "red")
    return s


WALL_MATERIALS = ["wood", "timber", "stone", "fortress"]


def tower_art(kind, stage):
    """A wall slot's defensive work in three stages."""
    s = Svg()
    plot_ground(s, ("#9a8a68", "#6e5f45"))
    big = [0, 0.8, 0.95, 1.1][stage]
    stone = "stone" if stage > 1 else "wood"
    if kind == "archer_tower":
        round_tower(s, 64, 112, 34 * big, 66 * big, roof="red" if stage < 3 else "slate", wall_kind=stone)
        for dx in (-8, 4):
            s.line(64 + dx, 112 - 60 * big, 64 + dx + 10, 112 - 70 * big, stroke="#3a2a1c", sw=2)
    elif kind == "gate_tower":
        w = 52 * big
        soft_shadow(s, 66, 112, w * 0.7, 10, 0.35)
        s.rect(64 - w / 2, 112 - 70 * big, w, 70 * big, s.lin([(0, "#cfc9bd"), (1, "#7d776d")], 0, 0, 1, 0), stroke="none", sw=0)
        s.path(f"M{64 - w * 0.22},112 L{64 - w * 0.22},{112 - 30 * big} Q64,{112 - 42 * big} {64 + w * 0.22},{112 - 30 * big} L{64 + w * 0.22},112 Z", "#2b211a", stroke="none", sw=0)
        for i in range(4):
            s.line(64 - w * 0.18 + i * w * 0.12, 112 - 34 * big, 64 - w * 0.18 + i * w * 0.12, 112, stroke="#6b665f", sw=1.6)
        for i in range(4):
            s.rect(64 - w / 2 + i * w / 3.5, 112 - 78 * big, w / 7, 8, "#b8b2a6", stroke="none", sw=0)
    elif kind == "ballista":
        soft_shadow(s, 66, 112, 40, 9, 0.35)
        s.rect(26, 92, 76, 18, s.lin([(0, "#cfc9bd"), (1, "#8a847a")], 0, 0, 0, 1), stroke="none", sw=0)
        s.path("M34,70 Q64,52 94,70", "none", stroke="#6e4b2c", sw=5 * big)
        s.line(64, 90, 64, 64, stroke="#5b3f25", sw=5)
        s.line(30, 74, 98, 62, stroke="#c9c3b7", sw=3)
        s.poly([(98, 62), (88, 58), (90, 68)], "#8d98a6", stroke="none", sw=0)
        s.line(34, 70, 64, 76, stroke="#efe6d2", sw=1.2)
        s.line(94, 70, 64, 76, stroke="#efe6d2", sw=1.2)
    elif kind == "murder_holes":
        wall(s, 16, 112, 112, 40 * big)
        for x in (36, 64, 92):
            s.rect(x - 7, 112 - 46 * big, 14, 8, "#3a3631", stroke="none", sw=0)
            s.circle(x, 112 - 54 * big, 7, s.rad([(0, "#ffffff", 0.6), (1, "#ffffff", 0)]), stroke="none", sw=0)
    elif kind == "ditch":
        s.ellipse(64, 100, 52, 14, s.rad([(0, "#3e3428"), (1, "#5d4e3a")]), stroke="none", sw=0)
        if stage == 3:
            s.ellipse(64, 101, 44, 9, s.rad([(0, "#5f95ad"), (1, "#2c5571")]), stroke="none", sw=0)
        for i in range(4 + stage * 2):
            x = 18 + i * (92 / (3 + stage * 2))
            s.line(x, 92, x + 6, 74, stroke="#7a5636", sw=3)
    elif kind == "watchtower":
        h = 70 * big
        soft_shadow(s, 66, 112, 22, 6, 0.35)
        for x0, x1 in ((52, 58), (76, 70)):
            s.line(x0, 112, x1, 112 - h, stroke="#6e4b2c", sw=5)
        s.line(54, 112 - h * 0.45, 74, 112 - h * 0.62, stroke="#5b3f25", sw=3)
        house(s, 64, 112 - h, 28, 10, roof="thatch" if stage < 3 else "red", wall="wood", door=False)
        banner_pole(s, 64, 112 - h - 22, 20)
    return s


def field(kind, stage):
    s = Svg()
    ground = {"woodcutter": ("#7f9a52", "#4e6635"), "quarry": ("#b0a476", "#7e7350"), "farm": ("#b9b26a", "#857c43"), "iron_mine": ("#8f8a80", "#5f5b54")}[kind]
    s.circle(64, 66, 58, s.rad([(0, ground[0]), (1, ground[1])], 0.4, 0.35, 0.75), stroke="none", sw=0)
    if kind == "woodcutter":
        for x, foot, size in [(40, 70, 40), (66, 58, 46), (90, 72, 40)][: stage]:
            conifer(s, x, foot, size * 0.62, size, ("#7f9a52", "#4f6b37", "#2b3f24"))
        for i in range(stage):
            s.rect(34 + i * 8, 94 - i * 6, 46, 10, s.lin([(0, "#c08a55"), (1, "#5a3a1f")], 0, 0, 0, 1), stroke="none", sw=0, rx=5)
    elif kind == "quarry":
        s.poly([(22, 96), (34, 62), (60, 54), (72, 78), (62, 98)], s.lin([(0, "#d8d2c6"), (1, "#7d776d")], 0, 0, 1, 1), stroke="none", sw=0)
        for i in range(stage):
            x, y = 72 + (i % 2) * 16, 96 - (i // 2) * 12 - i * 4
            s.rect(x, y - 12, 18, 12, s.lin([(0, "#e4ded3"), (1, "#9a948a")], 0, 0, 1, 1), stroke="none", sw=0)
        if stage == 3:
            s.line(98, 100, 98, 40, stroke="#6e4b2c", sw=4)
            s.line(98, 40, 70, 48, stroke="#6e4b2c", sw=3)
    elif kind == "farm":
        rows = stage + 2
        for i in range(rows):
            y = 46 + i * (56 / rows)
            s.rect(22, y, 84, 56 / rows * 0.6, s.lin([(0, "#f2d77e"), (1, "#b48d3e")], 0, 0, 0, 1), stroke="none", sw=0, rx=3)
        if stage >= 2:
            house(s, 94, 104, 22, 12, roof="thatch", wall="wood", door=False)
    else:  # iron_mine
        s.path("M28,104 Q34,48 64,44 Q94,48 100,104 Z", s.rad([(0, "#a49e94"), (1, "#57534c")], 0.38, 0.3, 0.8), stroke="none", sw=0)
        s.path("M48,104 Q50,72 64,70 Q78,72 80,104 Z", "#141110", stroke="none", sw=0)
        s.rect(44, 66, 40, 6, s.lin([(0, "#a8794a"), (1, "#5b3f25")], 0, 0, 0, 1), stroke="none", sw=0)
        if stage >= 2:
            cart(s, 100, 112, 26)
        if stage == 3:
            s.rect(14, 76, 16, 30, s.lin([(0, "#c9c3b7"), (1, "#6a655d")], 0, 0, 1, 0), stroke="none", sw=0)
            s.circle(22, 66, 8, s.rad([(0, "#4d4842", 0.6), (1, "#4d4842", 0)]), stroke="none", sw=0)
            s.circle(22, 72, 4, GLOW, stroke="none", sw=0)
    return s


def plot(kind):
    s = Svg()
    if kind == "empty":
        plot_ground(s, ("#a8987a", "#7d6f53"))
        for x, y in [(20, 100), (108, 100), (64, 86), (64, 118)]:
            s.line(x, y, x, y - 14, stroke="#6e4b2c", sw=3.5)
        s.path("M20,92 L64,78 L108,92", "none", stroke="#efe6d2", sw=1.2, opacity=0.8)
    else:  # locked: dark, bramble-grown ground under a padlock
        plot_ground(s, ("#4d4537", "#2f2a22"))
        for x, y in [(30, 104), (98, 104), (48, 114), (82, 114)]:
            tuft(s, x, y, color="#46552e", size=9)
        s.path("M54,80 L54,70 A10 10 0 0 1 74,70 L74,80", "none", stroke="#d8d2c4", sw=4)
        s.rect(48, 78, 32, 24, s.lin([(0, "#cfc9bd"), (1, "#7d776d")], 0, 0, 1, 1), stroke="none", sw=0, rx=3)
        s.circle(64, 88, 3.5, "#1d1813", stroke="none", sw=0)
        s.line(64, 90, 64, 96, stroke="#1d1813", sw=3)
    return s

def banner(part):
    """The owner's banner: the cloth is white so the game can tint it."""
    s = Svg(64, 96)
    if part == "pole":
        s.line(14, 92, 14, 8, stroke=s.lin([(0, "#a8794a"), (1, "#4f3822")], 0, 0, 1, 0), sw=4)
        s.circle(14, 7, 4, s.rad([(0, "#fff3b8"), (1, "#a77a17")], 0.35, 0.3, 0.8), stroke="none", sw=0)
    else:
        # White with soft folds, so the tint keeps its shading.
        s.path("M16,12 L58,16 L50,30 L58,44 L16,48 Z", s.lin([(0, "#ffffff"), (0.5, "#e9e9e9"), (1, "#bdbdbd")], 0, 0, 1, 0), stroke="none", sw=0)
        s.path("M28,13 L30,47", "none", stroke="#9a9a9a", sw=2, opacity=0.35)
        s.path("M42,15 L40,46", "none", stroke="#9a9a9a", sw=2, opacity=0.25)
    return s


def app_icon():
    """The launcher icon: the game's emblem on a dusk-dark tile."""
    s = Svg(192, 192)
    s.rect(4, 4, 184, 184, s.rad([(0, "#2b2a45"), (0.7, "#141a2c"), (1, "#0b0f19")], 0.5, 0.35, 0.85), stroke="none", sw=0, rx=40)
    s.embed(emblem(), 96 - 128 * 0.66, 92 - 124 * 0.66, 0.66)
    return s


def ui_title():
    """The start screen's picture: the Holy City over the Smorodina and the
    Kalinov Bridge, between dark woods, at dusk."""
    s = Svg(360, 180)
    s.rect(0, 0, 360, 180, s.lin([(0, "#2a3446"), (0.55, "#b9805a"), (1, "#e7b46f")]), stroke="none", sw=0)
    s.circle(282, 70, 26, s.rad([(0, "#fff1c4"), (0.4, "#f6c46e", 0.9), (1, "#f6c46e", 0)]), stroke="none", sw=0)
    s.path("M0,104 Q60,70 130,90 Q200,60 260,84 Q320,66 360,88 L360,180 L0,180 Z", s.lin([(0, "#5c5a63"), (1, "#3b3a42")]), stroke="none", sw=0)
    s.path("M0,126 Q90,98 180,112 Q270,96 360,122 L360,180 L0,180 Z", s.lin([(0, "#4d5b3a"), (1, "#2c3624")]), stroke="none", sw=0)
    s.embed(holy_city(), 128, 18, 0.65)
    for x, foot, size in [(18, 134, 34), (40, 142, 40), (10, 156, 36), (322, 130, 34), (344, 144, 40), (302, 154, 34)]:
        conifer(s, x, foot, size * 0.6, size, ("#3e5240", "#26362a", "#141d17"))
    s.path("M0,158 Q100,144 180,154 Q260,164 360,148 L360,180 L0,180 Z", s.lin([(0, "#c96d3c"), (1, "#7a2e18")]), stroke="none", sw=0)
    s.path("M30,168 Q60,162 90,168 M220,166 Q250,160 280,166", "none", stroke="#ffd27a", sw=2, opacity=0.7)
    s.path("M120,158 Q180,120 240,158", "none", stroke="#3b3a42", sw=12)
    s.path("M120,158 Q180,120 240,158", "none", stroke="#a39d92", sw=7)
    for x in (150, 180, 210):
        s.line(x, 158 - (24 if x == 180 else 16), x, 168, stroke="#6a655d", sw=4)
    return s

def ui_hero():
    """The start screen's painting, large enough to fill half a desktop or the
    top of a phone: dusk over the Smorodina, ranges fading into the haze, the
    Holy City on its hill, the Kalinov Bridge over the river of fire, dark
    woods at the edges; open sky above for the logo."""
    import random

    rnd = random.Random(11)
    s = Svg(1200, 1000)
    s.rect(0, 0, 1200, 1000, s.lin([(0, "#0f1424"), (0.34, "#2b2a45"), (0.56, "#7a4c58"), (0.7, "#d48a5c"), (0.8, "#f2b56c")]), stroke="none", sw=0)
    for _ in range(90):
        x, y = rnd.uniform(0, 1200), rnd.uniform(0, 420)
        s.circle(x, y, rnd.uniform(0.8, 2.2), "#fff4cf", stroke="none", sw=0, opacity=round(rnd.uniform(0.25, 0.85) * (1 - y / 520), 2))
    s.circle(820, 690, 260, s.rad([(0, "#ffe7b0", 0.85), (0.3, "#f6c46e", 0.45), (1, "#f6c46e", 0)]), stroke="none", sw=0)
    s.circle(820, 690, 70, s.rad([(0, "#fff6dc"), (0.6, "#ffe0a0"), (1, "#f6c46e", 0)]), stroke="none", sw=0)
    # Ranges, palest and haziest furthest away (aerial perspective).
    ranges = [
        ("M0,640 L90,580 L170,612 L260,540 L360,600 L450,560 L560,620 L640,570 L760,630 L860,560 L980,610 L1080,570 L1200,620 L1200,1000 L0,1000 Z", ("#8a6a78", "#6d5466"), 0.85),
        ("M0,700 Q80,640 170,672 Q260,610 360,668 Q470,626 560,690 Q680,640 780,700 Q900,650 1010,690 Q1110,660 1200,700 L1200,1000 L0,1000 Z", ("#5d4a5e", "#3f3346"), 1),
        ("M0,770 Q120,720 260,748 Q400,712 520,744 Q700,700 860,750 Q1020,716 1200,756 L1200,1000 L0,1000 Z", ("#3a3a3c", "#262629"), 1),
    ]
    for d, (a, b), op in ranges:
        s.path(d, s.lin([(0, a), (1, b)]), stroke="none", sw=0, opacity=op)
    # The hill and the city on it.
    s.path("M400,850 Q530,770 640,780 Q760,772 860,850 Z", s.lin([(0, "#4b5a3a"), (1, "#2c3624")]), stroke="none", sw=0)
    s.embed(holy_city(), 512, 640, 1.3)
    # Woods at the edges, nearest darkest.
    for x, foot, size in [(40, 860, 150), (120, 900, 190), (230, 880, 140), (10, 960, 220), (980, 870, 150), (1080, 900, 200), (1160, 880, 150), (900, 940, 170), (330, 930, 120)]:
        conifer(s, x, foot, size * 0.6, size, ("#26332a", "#17211b", "#0b110d"))
    # The Smorodina, the river of fire, and the Kalinov Bridge.
    s.path("M0,880 Q200,850 420,872 Q600,890 800,868 Q1000,848 1200,876 L1200,1000 L0,1000 Z", s.lin([(0, "#e98a46"), (0.6, "#b24a20"), (1, "#5e1d0e")]), stroke="none", sw=0)
    for x0, y0 in ((120, 912), (520, 920), (860, 906), (1040, 930)):
        s.path(f"M{x0},{y0} Q{x0 + 60},{y0 - 10} {x0 + 120},{y0}", "none", stroke="#ffd27a", sw=4, opacity=0.65)
    # The Kalinov Bridge: stone piers in the fire, then the arched deck on
    # them, its courses lit from above and its underside in shade.
    def deck_y(x):
        return 912 - 92 * (1 - ((x - 600) / 230) ** 2)

    for x in (500, 600, 700):
        s.rect(x - 11, deck_y(x) + 10, 22, 960 - deck_y(x) - 10, s.lin([(0, "#8f8472"), (1, "#4a4038")], 0, 0, 1, 0), stroke="none", sw=0)
    s.path("M370,912 Q600,728 830,912", "none", stroke="#1c1820", sw=36)
    s.path("M370,918 Q600,734 830,918", "none", stroke="#5f564b", sw=14)
    s.path("M370,906 Q600,722 830,906", "none", stroke=s.lin([(0, "#f3e9d3"), (1, "#b3a78f")]), sw=16)
    for i in range(1, 12):
        x = 370 + 460 * i / 12
        y = deck_y(x) - 6
        s.line(x, y - 7, x, y + 7, stroke="#8a7f6c", sw=2)
    # A low mist over the river, and the night closing in at the top.
    s.rect(0, 840, 1200, 160, s.lin([(0, "#ffffff", 0), (0.5, "#f6d7b0", 0.10), (1, "#ffffff", 0)]), stroke="none", sw=0)
    return s


# --- The game's brand: emblem, wordmark and logo -----------------------------
# A gold lozenge, the "sown field" of Slavic embroidery, framing the Holy City
# and the Kalinov Bridge at dusk; under it SLAVIAN in Ruslan Display, its
# letters cut from the font as paths and plated in gold.

GOLD_PLATE = [(0, "#fff4c2"), (0.32, "#ecc457"), (0.58, "#b8862a"), (0.82, "#7a5512"), (1, "#c99a3a")]
FONT_DIR = ROOT / "client" / "ui" / "fonts"


def lozenge(cx, cy, rx, ry):
    return [(cx, cy - ry), (cx + rx, cy), (cx, cy + ry), (cx - rx, cy)]


def emblem():
    s = Svg(256, 256)
    soft_shadow(s, 132, 246, 70, 8, 0.4)
    # The plate: a gold lozenge with a dark bevel, lit from the upper left.
    s.poly(lozenge(128, 124, 122, 122), "#2a1a08", stroke="none", sw=0)
    s.poly(lozenge(128, 124, 118, 118), s.lin(GOLD_PLATE, 0, 0, 1, 1), stroke="none", sw=0)
    s.poly(lozenge(128, 124, 104, 104), s.lin([(0, "#7a5512"), (1, "#fff1b8")], 0, 0, 1, 1), stroke="none", sw=0)
    # The field, clipped to the inner lozenge: dusk over the Smorodina.
    clip = f"c{next(GRADIENT_IDS)}"
    s.defs.append(f'<clipPath id="{clip}"><polygon points="{pts(lozenge(128, 124, 100, 100))}"/></clipPath>')
    field = Svg(256, 256)
    field.rect(0, 0, 256, 256, field.lin([(0, "#151c33"), (0.45, "#3d3350"), (0.72, "#b06a4c"), (1, "#f0b468")]), stroke="none", sw=0)
    field.circle(170, 128, 30, field.rad([(0, "#fff4cf"), (0.35, "#ffd37a", 0.95), (1, "#f6c46e", 0)]), stroke="none", sw=0)
    for x, y, r in ((92, 70, 1.6), (120, 52, 1.2), (150, 64, 1.4), (104, 92, 1.0), (176, 86, 1.1)):
        field.circle(x, y, r, "#fff4cf", stroke="none", sw=0, opacity=0.8)
    field.path("M20,150 Q70,122 120,138 Q170,116 236,140 L236,256 L20,256 Z", field.lin([(0, "#4f4a58"), (1, "#2c2934")]), stroke="none", sw=0)
    field.embed(holy_city(), 84, 66, 0.62)
    for x, foot, size in ((58, 172, 30), (74, 180, 36), (186, 174, 32), (200, 182, 38)):
        conifer(field, x, foot, size * 0.6, size, ("#2f3d33", "#1d2820", "#0f1611"))
    # The river of fire and the bridge over it.
    field.path("M20,184 Q90,172 128,180 Q170,188 236,176 L236,256 L20,256 Z", field.lin([(0, "#e0773a"), (1, "#7a2a14")]), stroke="none", sw=0)
    field.path("M60,196 Q90,190 118,196 M146,192 Q176,186 204,192", "none", stroke="#ffd27a", sw=2, opacity=0.75)
    field.path("M78,186 Q128,148 178,186", "none", stroke="#2a2430", sw=11)
    field.path("M78,186 Q128,148 178,186", "none", stroke=field.lin([(0, "#e8dcc2"), (1, "#9a8f7c")]), sw=6)
    for x in (102, 128, 154):
        field.line(x, 186 - (14 if x == 128 else 8), x, 198, stroke="#4a4038", sw=3.5)
    s.defs.extend(field.defs)
    s.add(f'<g clip-path="url(#{clip})">{"".join(field.parts)}</g>')
    # Bevel lines and the four "seeds" of the sown field at the plate's points.
    s.poly(lozenge(128, 124, 100, 100), "none", stroke="#3a2608", sw=2)
    s.poly(lozenge(128, 124, 112, 112), "none", stroke="#fff4c2", sw=1, opacity=0.6)
    for x, y in ((128, 14), (238, 124), (128, 234), (18, 124)):
        s.poly(lozenge(x, y, 7, 7), "#3a2608", stroke="none", sw=0)
        s.poly(lozenge(x, y, 4, 4), s.lin(GOLD_PLATE, 0, 0, 1, 1), stroke="none", sw=0)
    return s


def wordmark_paths(text, size, tracking=-40):
    """The text's outlines in Ruslan Display: (paths, width, height), each
    path a (d, x offset) in font units scaled to `size` px per em."""
    from fontTools.pens.svgPathPen import SVGPathPen
    from fontTools.ttLib import TTFont

    font = TTFont(str(FONT_DIR / "RuslanDisplay-Regular.ttf"))
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    scale = size / font["head"].unitsPerEm
    out, x = [], 0.0
    for ch in text:
        name = cmap[ord(ch)]
        pen = SVGPathPen(glyphs)
        glyphs[name].draw(pen)
        out.append((pen.getCommands(), x))
        x += glyphs[name].width + tracking
    return out, (x - tracking) * scale, scale


def wordmark(text="SLAVIAN", size=120):
    """The name plated in gold over a dark bevel, a soft shadow under it."""
    paths, width, scale = wordmark_paths(text, size)
    cap = 500 * scale
    pad = 14
    s = Svg(round(width + pad * 2), round(cap + 112 * scale + pad * 2))
    base = pad + cap

    def letters(fill, stroke, sw, dx=0.0, dy=0.0, opacity=1):
        for d, x in paths:
            s.add(
                f'<path transform="translate({fmt(pad + x * scale + dx)},{fmt(base + dy)}) scale({fmt(scale)},{fmt(-scale)})" d="{d}" '
                f'fill="{fill}" stroke="{stroke}" stroke-width="{fmt(sw / scale)}" stroke-linejoin="round" opacity="{opacity}"/>'
            )

    letters("#000000", "#000000", 6, 2, 5, 0.45)
    letters("#2a1a08", "#2a1a08", 7)
    # The glyphs are drawn flipped (font units grow upwards), so the plate's
    # gradient runs from the box's bottom to its top to light them from above.
    letters(s.lin(GOLD_PLATE, 0, 1, 0, 0), "#fff4c2", 1.2)
    return s


def logo():
    """The lockup: the emblem over the wordmark and a lozenge rule under it."""
    mark = wordmark(size=128)
    s = Svg(max(560, mark.w + 20), 300 + mark.h + 30)
    s.embed(emblem(), (s.w - 256) / 2 + 2, 4, 1.0)
    s.embed(mark, (s.w - mark.w) / 2, 270, 1.0)
    y = 270 + mark.h + 10
    gold = s.lin(GOLD_PLATE, 0, 0, 0, 1)
    for x0, x1 in ((s.w / 2 - 190, s.w / 2 - 18), (s.w / 2 + 18, s.w / 2 + 190)):
        s.rect(x0, y - 1.5, x1 - x0, 3, gold, stroke="none", sw=0)
    s.poly(lozenge(s.w / 2, y, 11, 11), "#2a1a08", stroke="none", sw=0)
    s.poly(lozenge(s.w / 2, y, 8, 8), s.lin(GOLD_PLATE, 0, 0, 1, 1), stroke="none", sw=0)
    return s


# --- Build everything --------------------------------------------------------

def assets():
    out = {}
    for kind, make in FEATURES.items():
        out[f"feature/{kind}"] = make()
    for tier in range(1, 6):
        out[f"settlement/village_{tier}"] = settlement(tier)
    out["settlement/ruins"] = ruins()
    out["settlement/holy_city"] = holy_city()
    out["banner/pole"] = banner("pole")
    out["banner/cloth"] = banner("cloth")
    out["map/camp_bandit"] = camp("bandit")
    out["map/camp_lair"] = camp("lair")
    out["map/fort"] = fort()
    out["map/outpost"] = outpost()
    for kind in ["kurgan", "sunken_shrine", "old_hillfort", "stone_idol", "frozen_ruin"]:
        out[f"site/{kind}"] = site(kind)
    for kind in ["spearman", "archer", "horseman", "scout", "settler", "forest_archer", "river_barge", "border_rider"]:
        out[f"unit/{kind}"] = unit(kind)
    for front in ["north", "east", "order"]:
        out[f"faction/{front}"] = faction(front)
    for units in ENEMY_UNITS.values():
        for kind in units:
            out[f"unit/{kind}"] = enemy(kind)
    for kind in ["wood", "stone", "grain", "iron", "ember"]:
        out[f"resource/{kind}"] = resource(kind)
    out["app/icon"] = app_icon()
    for kind in VILLAGE_BUILDINGS:
        for stage in (1, 2, 3):
            out[f"building/{kind}_{stage}"] = building(kind, stage)
    for material in WALL_MATERIALS:
        out[f"building/wall_{material}"] = wall_gate(material)
    for stage in (1, 2, 3):
        for kind in WALL_TOWERS:
            out[f"building/{kind}_{stage}"] = tower_art(kind, stage)
    for kind in FIELDS:
        for stage in (1, 2, 3):
            out[f"field/{kind}_{stage}"] = field(kind, stage)
    out["plot/empty"] = plot("empty")
    out["plot/locked"] = plot("locked")
    out["ui/title"] = ui_title()
    out["ui/hero"] = ui_hero()
    out["brand/emblem"] = emblem()
    out["brand/wordmark"] = wordmark()
    out["brand/logo"] = logo()
    for kind in UI_ICONS:
        out[f"icon/{kind}"] = icon(kind)
    return out


# Pieces drawn at full size already, imported 1:1 (2x would cost a phone
# 19 MB of video memory for the start screen's painting).
FULL_SIZE = {"ui/hero"}


def set_import_scale(svg_path, scale=IMPORT_SCALE):
    """Godot reads its import settings from <file>.import; a minimal one is
    completed by Godot on the next import."""
    imp = svg_path.with_name(svg_path.name + ".import")
    if not imp.exists():
        imp.write_text(f'[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\nsvg/scale={scale}\n')
        return
    lines = imp.read_text().splitlines()
    lines = [f"svg/scale={scale}" if line.startswith("svg/scale=") else line for line in lines]
    imp.write_text("\n".join(lines) + "\n")


def textures():
    """Raster pieces (PNG), made with numpy and Pillow: the interface's wood."""
    try:
        from wood import wood
    except ImportError:
        print("numpy or Pillow missing: ui/wood left as it is")
        return {}
    return {"ui/wood": wood()}


def main():
    manifest = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}
    made = assets()
    # Generated art that is no longer made goes; your own stays.
    manifest = {k: v for k, v in manifest.items() if k in made or not v.startswith(RES)}
    for art_id, svg in made.items():
        path = OUT_DIR / f"{art_id}.svg"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(svg.text())
        set_import_scale(path, 1.0 if art_id in FULL_SIZE else IMPORT_SCALE)
        res = f"{RES}/{art_id}.svg"
        # Your own art (a path outside generated/) is never replaced.
        if not manifest.get(art_id, res).startswith(RES):
            continue
        manifest[art_id] = res
    for art_id, image in textures().items():
        path = OUT_DIR / f"{art_id}.png"
        path.parent.mkdir(parents=True, exist_ok=True)
        image.save(path)
        if manifest.get(art_id, f"{RES}/{art_id}.png").startswith(RES):
            manifest[art_id] = f"{RES}/{art_id}.png"
    MANIFEST.write_text(json.dumps(dict(sorted(manifest.items())), indent=2) + "\n")
    print(f"{len(manifest)} art ids in {MANIFEST.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
