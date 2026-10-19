#!/usr/bin/env python3
"""Generates Slavian's first set of art as SVG (docs/art-style.md).

Every asset is built from the same palette and the same few rules (a dark
outline, flat fills with one highlight, a soft ground shadow), so the set
stays consistent. Files go to client/art/generated/; client/art/art.json maps
art ids to files. Entries that point somewhere else (your own art) are never
touched, so you can replace any asset by pointing its id at your file.

    python3 tools/art/generate.py
"""
import json
import math
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


class Svg:
    def __init__(self, w=128, h=128):
        self.w, self.h = w, h
        self.parts = []

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
        return self.add(f'<line x1="{fmt(x1)}" y1="{fmt(y1)}" x2="{fmt(x2)}" y2="{fmt(y2)}" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" opacity="{opacity}"/>')

    def shadow(self, cx, cy, rx, ry=None):
        return self.ellipse(cx, cy, rx, ry if ry is not None else rx * 0.28, SHADOW, stroke="none", sw=0, opacity=0.25)

    def embed(self, other, x, y, scale=1.0):
        """Draws another piece inside this one, its top left at (x, y)."""
        body = "".join(other.parts)
        return self.add(f'<g transform="translate({fmt(x)},{fmt(y)}) scale({scale})">{body}</g>')

    def text(self):
        body = "\n  ".join(self.parts)
        return f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" viewBox="0 0 {self.w} {self.h}">\n  {body}\n</svg>\n'


# --- Shared pieces -----------------------------------------------------------
HEX_W = 128
HEX_H = round(128 * 2 / math.sqrt(3))  # pointy-top: 148


def hex_points(w=HEX_W, h=HEX_H, inset=0):
    cx, cy = w / 2, h / 2
    r = h / 2 - inset
    return [(cx + r * math.cos(math.radians(60 * i - 90)), cy + r * math.sin(math.radians(60 * i - 90))) for i in range(6)]


def tree(s, x, y, size, kind="forest"):
    base, light = P[kind]
    s.rect(x - size * 0.08, y - size * 0.1, size * 0.16, size * 0.3, P["wood"][0], sw=2.5)
    s.poly([(x, y - size), (x + size * 0.45, y), (x - size * 0.45, y)], base, sw=3)
    s.poly([(x, y - size * 0.92), (x + size * 0.18, y - size * 0.5), (x - size * 0.1, y - size * 0.55)], light, stroke="none", sw=0)


def round_tree(s, x, y, size):
    s.rect(x - size * 0.08, y, size * 0.16, size * 0.35, P["wood"][0], sw=2.5)
    s.circle(x, y - size * 0.15, size * 0.42, P["forest"][0], sw=3)
    s.circle(x - size * 0.12, y - size * 0.3, size * 0.15, P["forest"][1], stroke="none", sw=0)


def tuft(s, x, y, color=INK, size=8):
    s.path(f"M{fmt(x - size * 0.6)},{fmt(y)} L{fmt(x - size * 0.3)},{fmt(y - size)} M{fmt(x)},{fmt(y)} L{fmt(x)},{fmt(y - size * 1.2)} M{fmt(x + size * 0.6)},{fmt(y)} L{fmt(x + size * 0.3)},{fmt(y - size)}", "none", stroke=color, sw=2.5)


def wave(s, x, y, w=22, color="#ffffff", sw=3, opacity=0.8):
    s.path(f"M{fmt(x - w / 2)},{fmt(y)} q{fmt(w / 4)},-6 {fmt(w / 2)},0 t{fmt(w / 2)},0", "none", stroke=color, sw=sw, opacity=opacity)


def peak(s, x, y, w, h, snow=True, color="rock"):
    base, light = P[color]
    s.poly([(x - w / 2, y), (x, y - h), (x + w / 2, y)], base, sw=3.5)
    s.poly([(x, y - h), (x + w * 0.12, y - h * 0.45), (x - w * 0.05, y - h * 0.55), (x - w * 0.18, y - h * 0.35)], light, stroke="none", sw=0)
    if snow:
        s.poly([(x - w * 0.16, y - h * 0.68), (x, y - h), (x + w * 0.16, y - h * 0.68), (x + w * 0.06, y - h * 0.74), (x - w * 0.04, y - h * 0.66)], P["snow"][0], sw=2.5)


def hut(s, x, y, w, roof="thatch", wall="wood"):
    """A hut whose base centre is (x, y)."""
    h = w * 0.55
    s.rect(x - w / 2, y - h, w, h, P[wall][0], sw=3)
    s.rect(x - w * 0.12, y - h * 0.6, w * 0.24, h * 0.6, INK, sw=0)
    s.poly([(x - w * 0.62, y - h), (x, y - h - w * 0.55), (x + w * 0.62, y - h)], P[roof][0], sw=3)
    s.poly([(x, y - h - w * 0.5), (x + w * 0.45, y - h - 2), (x + w * 0.15, y - h - 2)], P[roof][1], stroke="none", sw=0)


def hall(s, x, y, w, roof="roof"):
    h = w * 0.5
    s.rect(x - w / 2, y - h, w, h, P["wood"][0], sw=3.5)
    s.rect(x - w * 0.1, y - h * 0.65, w * 0.2, h * 0.65, INK, sw=0)
    s.poly([(x - w * 0.6, y - h), (x - w * 0.35, y - h - w * 0.42), (x + w * 0.35, y - h - w * 0.42), (x + w * 0.6, y - h)], P[roof][0], sw=3.5)
    s.poly([(x - w * 0.3, y - h - w * 0.38), (x + w * 0.3, y - h - w * 0.38), (x + w * 0.45, y - h - 3), (x - w * 0.1, y - h - 3)], P[roof][1], stroke="none", sw=0)
    # Carved gable horns.
    s.path(f"M{fmt(x - w * 0.35)},{fmt(y - h - w * 0.42)} l-6,-8 M{fmt(x + w * 0.35)},{fmt(y - h - w * 0.42)} l6,-8", "none", sw=3)


def palisade(s, x0, x1, y, h=16):
    n = max(3, int((x1 - x0) / 8))
    step = (x1 - x0) / n
    for i in range(n + 1):
        x = x0 + i * step
        s.poly([(x - 3.5, y), (x - 3.5, y - h), (x, y - h - 5), (x + 3.5, y - h), (x + 3.5, y)], P["wood"][1], sw=2.5)


def stone_wall(s, x0, x1, y, h=18):
    s.rect(x0, y - h, x1 - x0, h, P["stone"][0], sw=3.5)
    for i in range(int((x1 - x0) / 12) + 1):
        x = x0 + i * 12
        s.rect(x, y - h - 6, 7, 6, P["stone"][0], sw=2.5)
    s.line(x0 + 3, y - h / 2, x1 - 3, y - h / 2, sw=1.5, opacity=0.5)


def tower(s, x, y, w=18, h=40, roof="roof", wall="stone"):
    s.rect(x - w / 2, y - h, w, h, P[wall][0], sw=3)
    s.rect(x - w * 0.15, y - h * 0.7, w * 0.3, h * 0.2, INK, sw=0)
    s.poly([(x - w * 0.7, y - h), (x, y - h - w * 1.1), (x + w * 0.7, y - h)], P[roof][0], sw=3)


def onion(s, x, y, r, color="gold"):
    base, light = P[color]
    s.path(f"M{fmt(x - r)},{fmt(y)} C{fmt(x - r * 1.25)},{fmt(y - r * 1.2)} {fmt(x - r * 0.1)},{fmt(y - r * 1.5)} {fmt(x)},{fmt(y - r * 2.3)} C{fmt(x + r * 0.1)},{fmt(y - r * 1.5)} {fmt(x + r * 1.25)},{fmt(y - r * 1.2)} {fmt(x + r)},{fmt(y)} Z", base, sw=3)
    s.path(f"M{fmt(x - r * 0.45)},{fmt(y - r * 0.4)} C{fmt(x - r * 0.6)},{fmt(y - r * 1.0)} {fmt(x - r * 0.2)},{fmt(y - r * 1.4)} {fmt(x - r * 0.05)},{fmt(y - r * 1.8)}", "none", stroke=light, sw=3)
    s.line(x, y - r * 2.3, x, y - r * 2.9, sw=2.5)
    s.line(x - r * 0.25, y - r * 2.7, x + r * 0.25, y - r * 2.7, sw=2.5)


def medallion(s, color="cloth", ring="gold"):
    s.circle(64, 64, 56, P[ring][0], sw=4)
    s.circle(64, 64, 48, P[color][0], sw=3)


# --- Terrain tiles (pointy-top hexes, no outline: the map draws the grid) --

def terrain(base, motif):
    s = Svg(HEX_W, HEX_H)
    s.poly(hex_points(), P[base][0], stroke="none", sw=0)
    motif(s)
    return s


def m_plains(s):
    for x, y in [(40, 60), (82, 52), (64, 92), (30, 100), (96, 98)]:
        tuft(s, x, y, color="#55702f", size=11)
    for x, y, c in [(58, 66, "#f3d06a"), (90, 76, "#ffffff"), (44, 118, "#f3d06a"), (84, 122, "#ffffff")]:
        s.circle(x, y, 3.5, c, sw=1.5)


def m_forest(s):
    for x, y, z in [(42, 72, 34), (84, 66, 38), (62, 108, 36), (100, 104, 28), (28, 108, 26)]:
        tree(s, x, y, z)


def m_dark_forest(s):
    for x, y, z in [(40, 70, 38), (82, 62, 42), (60, 106, 40), (100, 104, 32), (26, 106, 30)]:
        tree(s, x, y, z, kind="dark_forest")
    for x, y in [(56, 84), (90, 86)]:
        s.circle(x, y, 2.2, "#f3d06a", stroke="none", sw=0)
        s.circle(x + 6, y, 2.2, "#f3d06a", stroke="none", sw=0)


def m_hills(s):
    for x, y, w in [(44, 80, 52), (86, 96, 56), (48, 118, 40)]:
        s.path(f"M{fmt(x - w / 2)},{fmt(y)} Q{fmt(x)},{fmt(y - w * 0.7)} {fmt(x + w / 2)},{fmt(y)} Z", P["hill"][0], sw=3)
        s.path(f"M{fmt(x - w * 0.2)},{fmt(y - w * 0.22)} Q{fmt(x)},{fmt(y - w * 0.36)} {fmt(x + w * 0.15)},{fmt(y - w * 0.26)}", "none", stroke=P["hill"][1], sw=3)


def m_mountain(s):
    peak(s, 50, 100, 64, 66)
    peak(s, 88, 112, 56, 54)
    peak(s, 70, 70, 40, 34, snow=False)


def m_swamp(s):
    for x, y, w in [(46, 76, 30), (86, 98, 34), (52, 112, 24)]:
        s.ellipse(x, y, w / 2, w / 5, P["mud"][0], sw=2.5)
    for x, y in [(70, 70), (30, 96), (100, 74), (78, 118)]:
        s.path(f"M{x},{y} l-4,-16 M{x},{y} l0,-20 M{x},{y} l5,-15", "none", stroke="#3d4a2a", sw=2.5)
        s.ellipse(x, y - 21, 2.5, 5, "#6b4a2a", stroke="none", sw=0)


def m_lake(s):
    for x, y in [(44, 64), (84, 80), (56, 100), (90, 112)]:
        wave(s, x, y)


def m_ocean(s):
    for x, y in [(40, 56), (80, 68), (48, 92), (88, 104), (60, 124)]:
        wave(s, x, y, w=26, opacity=0.55)


def m_ice(s):
    s.path("M30,70 L52,80 L48,96 L70,106 M80,56 L76,74 L96,86 M62,122 L72,110", "none", stroke="#9fb6c2", sw=2.5)
    for x, y in [(90, 112), (38, 112)]:
        s.poly([(x - 8, y), (x, y - 14), (x + 8, y)], P["snow"][0], sw=2.5)


def m_steppe(s):
    for x, y in [(36, 64), (76, 56), (96, 84), (56, 90), (34, 108), (84, 116)]:
        tuft(s, x, y, color="#8f7440", size=7)


def m_hallowed(s):
    s.ellipse(64, 92, 38, 18, P["hallow"][1], stroke="none", sw=0, opacity=0.6)
    for i in [3, 4, 5, 0, 2, 1]:  # back row first
        a = math.radians(60 * i)
        x, y = 64 + 34 * math.cos(a), 92 + 16 * math.sin(a)
        s.rect(x - 6, y - 28, 12, 28, P["stone"][0], sw=3, rx=4)
    s.circle(64, 90, 6, P["ember"][1], sw=2)


def m_holy_city(s):
    s.poly(hex_points(inset=26), P["wall"][1], stroke=P["stone"][0], sw=3, opacity=0.8)


TERRAIN = {
    "plains": ("grass", m_plains),
    "forest": ("grass", m_forest),
    "hills": ("hill", m_hills),
    "mountain": ("rock", m_mountain),
    "swamp": ("swamp", m_swamp),
    "lake": ("water", m_lake),
    "holy_city": ("meadow", m_holy_city),
    "ocean": ("deep", m_ocean),
    "dark_forest": ("dark_forest", m_dark_forest),
    "ice": ("ice", m_ice),
    "steppe": ("sand", m_steppe),
    "hallowed": ("hallow", m_hallowed),
}


# --- Settlements -----------------------------------------------------------

def settlement(tier):
    """Five looks as a village grows (Elder's Hall levels 1-2, 3-4, 5-6, 7-8, 9-10)."""
    s = Svg()
    s.shadow(64, 112, 54, 12)
    if tier == 1:
        hut(s, 44, 104, 34)
        hut(s, 84, 108, 28)
        s.circle(66, 112, 4, P["ember"][0], sw=2)
    elif tier == 2:
        palisade(s, 14, 114, 116, 12)
        hut(s, 40, 100, 32)
        hut(s, 88, 102, 30)
        hut(s, 64, 88, 30, roof="thatch")
    elif tier == 3:
        palisade(s, 10, 118, 118, 16)
        hut(s, 30, 102, 26)
        hut(s, 98, 104, 26)
        hall(s, 64, 98, 48, roof="thatch")
    elif tier == 4:
        palisade(s, 8, 120, 120, 18)
        tower(s, 18, 112, 16, 46, roof="thatch", wall="wood")
        tower(s, 110, 112, 16, 46, roof="thatch", wall="wood")
        hut(s, 38, 104, 24)
        hall(s, 70, 100, 56)
    else:
        stone_wall(s, 8, 120, 122, 20)
        tower(s, 16, 118, 20, 54)
        tower(s, 112, 118, 20, 54)
        hall(s, 64, 98, 62)
        onion(s, 64, 52, 8, color="gold")
    return s


def ruins():
    s = Svg()
    s.shadow(64, 112, 52, 12)
    s.poly([(24, 112), (24, 84), (32, 76), (40, 88), (40, 112)], P["wood"][0], sw=3)
    s.poly([(70, 112), (70, 90), (80, 82), (86, 96), (96, 92), (96, 112)], P["stone"][0], sw=3)
    s.line(44, 108, 64, 96, sw=4)
    for x, y, r in [(52, 64, 10), (60, 48, 13), (72, 30, 16)]:
        s.circle(x, y, r, "#6d655a", stroke="none", sw=0, opacity=0.55)
    s.circle(54, 104, 5, P["ember"][0], sw=2)
    return s


def holy_city():
    s = Svg(160, 160)
    s.shadow(80, 142, 70, 14)
    s.rect(14, 92, 132, 46, P["wall"][0], sw=4)
    for i in range(12):
        s.rect(14 + i * 11.6, 84, 7, 8, P["wall"][0], sw=2.5)
    s.path("M66,138 L66,114 Q80,98 94,114 L94,138 Z", INK, sw=0)
    for x in (28, 132):
        s.rect(x - 13, 66, 26, 72, P["wall"][0], sw=4)
        onion(s, x, 66, 12, color="gold")
    s.rect(52, 48, 56, 44, P["wall"][1], sw=4)
    onion(s, 80, 48, 22, color="gold")
    for x in (60, 100):
        onion(s, x, 50, 8, color="red")
    s.line(10, 92, 150, 92, sw=0)
    return s


def banner(part):
    """The owner's banner: the cloth is white so the game can tint it."""
    s = Svg(64, 96)
    if part == "pole":
        s.line(14, 92, 14, 6, stroke=INK, sw=7)
        s.line(14, 92, 14, 6, stroke=P["wood"][1], sw=3)
        s.circle(14, 6, 5, P["gold"][0], sw=2.5)
    else:
        s.path("M17,12 L58,16 L50,30 L58,44 L17,48 Z", P["cloth"][0], sw=3.5)
        s.path("M22,18 L50,20", "none", stroke="#d8d2c4", sw=3)
    return s


def camp(kind):
    s = Svg()
    s.shadow(64, 110, 52, 12)
    if kind == "bandit":
        for x, w, c in [(40, 44, "sand"), (88, 38, "red")]:
            s.poly([(x - w / 2, 106), (x, 106 - w * 0.95), (x + w / 2, 106)], P[c][0], sw=3.5)
            s.poly([(x - 5, 106), (x, 94), (x + 5, 106)], INK, sw=0)
        s.line(64, 112, 64, 44, sw=3)
        s.poly([(64, 44), (88, 50), (64, 58)], P["red"][0], sw=3)
        for i in range(3):
            s.line(56 + i * 7, 116, 62 + i * 3, 104, stroke=P["wood"][0], sw=3)
        s.circle(64, 108, 6, P["ember"][1], sw=2)
    else:
        s.path("M14,112 Q20,40 64,36 Q108,40 114,112 Z", P["rock"][0], sw=4)
        s.path("M36,112 Q40,62 64,60 Q88,62 92,112 Z", P["night"][0], sw=3)
        for x in (54, 74):
            s.ellipse(x, 84, 4.5, 3, "#f3d06a", stroke="none", sw=0)
        for x in (40, 60, 80):
            s.poly([(x, 112), (x + 4, 100), (x + 8, 112)], P["bone"][0], sw=2)
    return s


def fort():
    s = Svg()
    s.shadow(64, 112, 54, 12)
    palisade(s, 14, 114, 112, 26)
    tower(s, 64, 100, 22, 52, roof="thatch", wall="wood")
    s.line(64, 34, 64, 14, sw=3)
    s.poly([(64, 14), (84, 19), (64, 26)], P["cloth"][0], sw=3)
    return s


def outpost():
    s = Svg()
    s.shadow(64, 110, 44, 10)
    hut(s, 56, 108, 40)
    s.rect(84, 84, 22, 24, P["wood"][1], sw=3)
    s.line(84, 92, 106, 92, sw=2)
    s.line(84, 100, 106, 100, sw=2)
    return s


# --- Ancient sites ---------------------------------------------------------

def site(kind):
    s = Svg()
    s.shadow(64, 110, 50, 12)
    if kind == "kurgan":
        s.path("M10,110 Q64,30 118,110 Z", P["grass"][0], sw=4)
        s.path("M40,80 Q64,50 88,72", "none", stroke=P["grass"][1], sw=4)
        s.rect(58, 36, 12, 24, P["stone"][0], sw=3, rx=2)
    elif kind == "sunken_shrine":
        s.ellipse(64, 104, 54, 14, P["water"][0], sw=3)
        s.rect(40, 62, 48, 40, P["stone"][0], sw=3.5)
        s.poly([(34, 62), (64, 34), (94, 62)], P["stone"][1], sw=3.5)
        s.rect(58, 78, 12, 24, INK, sw=0)
        wave(s, 30, 104, 16)
        wave(s, 98, 106, 16)
    elif kind == "old_hillfort":
        s.ellipse(64, 92, 56, 24, P["hill"][0], sw=4)
        s.ellipse(64, 86, 38, 14, P["grass"][0], sw=3)
        for i in range(7):
            x = 34 + i * 10
            s.rect(x - 3, 66 + abs(i - 3) * 3, 6, 16, P["wood"][0], sw=2.5)
    elif kind == "stone_idol":
        s.rect(46, 18, 36, 92, P["stone"][0], sw=4, rx=4)
        s.rect(46, 18, 36, 18, P["stone"][1], sw=3, rx=4)
        for y in (46, 70, 92):
            s.line(50, y, 78, y, sw=2.5)
        for x in (56, 72):
            s.circle(x, 58, 3, INK, stroke="none", sw=0)
        s.path("M58,64 Q64,68 70,64", "none", sw=2.5)
    else:  # frozen_ruin
        s.ellipse(64, 104, 54, 12, P["ice"][0], sw=3)
        for x, h in [(34, 64), (64, 84), (94, 52)]:
            s.rect(x - 9, 104 - h, 18, h, P["ice"][1], sw=3.5)
            s.poly([(x - 9, 104 - h), (x - 3, 96 - h), (x + 4, 104 - h)], P["snow"][0], sw=2.5)
    return s


# --- Units, factions, resources -----------------------------------------------

def unit(kind):
    s = Svg()
    medallion(s)
    if kind in ("spearman",):
        s.line(40, 98, 92, 28, sw=7)
        s.line(40, 98, 92, 28, stroke=P["wood"][1], sw=3)
        s.poly([(92, 28), (98, 18), (86, 24)], P["iron"][1], sw=3)
        s.circle(52, 74, 22, P["red"][0], sw=4)
        s.circle(52, 74, 7, P["gold"][0], sw=3)
    elif kind in ("archer", "forest_archer"):
        s.path("M44,24 Q96,64 44,104", "none", stroke=INK, sw=8)
        s.path("M44,24 Q96,64 44,104", "none", stroke=P["wood"][1], sw=4)
        s.line(44, 24, 44, 104, sw=2)
        s.line(30, 64, 92, 64, sw=4)
        s.poly([(92, 64), (82, 58), (82, 70)], P["iron"][1], sw=3)
        if kind == "forest_archer":
            s.path("M86,30 Q104,26 100,46 Q84,48 86,30 Z", P["forest"][1], sw=3)
    elif kind in ("horseman", "border_rider"):
        s.path("M36,104 L44,64 Q46,36 70,30 L90,22 L86,36 Q98,46 96,62 L84,64 L80,54 L64,60 L62,104 Z", P["wood"][0], sw=4)
        s.path("M60,34 Q48,44 46,64", "none", stroke=INK, sw=6)
        s.circle(82, 40, 3, INK, stroke="none", sw=0)
        if kind == "border_rider":
            s.line(98, 100, 98, 26, sw=3)
            s.poly([(98, 26), (114, 32), (98, 38)], P["red"][0], sw=2.5)
    elif kind == "scout":
        s.path("M24,64 Q64,24 104,64 Q64,104 24,64 Z", P["cloth"][1], sw=4)
        s.circle(64, 64, 16, P["water"][0], sw=3)
        s.circle(64, 64, 6, INK, stroke="none", sw=0)
    elif kind == "settler":
        s.path("M28,74 Q64,30 100,74 Z", P["cloth"][0], sw=4)
        s.rect(28, 74, 72, 14, P["wood"][0], sw=3.5)
        for x in (42, 86):
            s.circle(x, 94, 11, P["wood"][1], sw=3.5)
            s.circle(x, 94, 3, INK, stroke="none", sw=0)
    elif kind == "river_barge":
        s.path("M22,74 L106,74 L94,94 L34,94 Z", P["wood"][0], sw=4)
        s.line(64, 74, 64, 30, sw=4)
        s.poly([(64, 32), (92, 66), (64, 66)], P["cloth"][0], sw=3)
        wave(s, 46, 104, 18, color=P["water"][0], sw=3.5, opacity=1)
        wave(s, 82, 104, 18, color=P["water"][0], sw=3.5, opacity=1)
    return s


def faction(front):
    s = Svg()
    if front == "north":
        medallion(s, color="dark_forest", ring="rock")
        for dx in (-16, 0, 16):
            s.path(f"M{64 + dx - 6},30 Q{64 + dx + 8},64 {64 + dx - 4},98", "none", stroke=P["bone"][0], sw=7)
    elif front == "east":
        medallion(s, color="sand", ring="red")
        s.line(64, 104, 64, 34, sw=4)
        s.circle(64, 30, 6, P["gold"][0], sw=3)
        s.path("M64,40 Q40,60 46,92 M64,40 Q64,70 60,96 M64,40 Q88,60 82,92", "none", stroke=INK, sw=6)
    else:  # the Order of the One Throne
        medallion(s, color="wall", ring="iron")
        s.path("M44,100 L44,52 Q44,36 64,30 Q84,36 84,52 L84,100", P["red"][0], sw=4)
        s.rect(38, 76, 52, 12, P["iron"][1], sw=3.5)
        s.poly([(50, 58), (50, 44), (57, 50), (64, 40), (71, 50), (78, 44), (78, 58)], P["gold"][0], sw=3)
    return s


def resource(kind):
    s = Svg()
    s.shadow(64, 110, 44, 10)
    if kind == "wood":
        for x, y in [(44, 96), (84, 96), (64, 70)]:
            s.rect(x - 24, y - 12, 48, 24, P["wood"][0], sw=3.5, rx=12)
            s.circle(x + 16, y, 9, P["wood"][1], sw=3)
            s.circle(x + 16, y, 3, INK, stroke="none", sw=0)
    elif kind == "stone":
        s.path("M22,106 L30,74 L56,62 L72,84 L66,106 Z", P["stone"][0], sw=3.5)
        s.path("M60,106 L68,58 L96,48 L108,80 L102,106 Z", P["stone"][1], sw=3.5)
        s.line(80, 60, 90, 76, sw=2)
    elif kind == "grain":
        for dx in (-14, 0, 14):
            s.line(64, 106, 64 + dx * 1.6, 30, stroke=P["thatch"][0], sw=6)
            s.ellipse(64 + dx * 1.6, 34, 7, 14, P["thatch"][0], sw=3)
        s.rect(46, 76, 36, 10, P["red"][0], sw=3, rx=3)
    elif kind == "iron":
        s.poly([(24, 98), (36, 72), (92, 72), (104, 98)], P["iron"][0], sw=4)
        s.poly([(40, 76), (88, 76), (84, 82), (44, 82)], P["iron"][1], stroke="none", sw=0)
    elif kind == "ember":
        s.circle(64, 72, 40, P["gold"][0], sw=4)
        s.path("M64,36 Q90,64 78,92 Q64,104 50,92 Q38,64 64,36 Z", P["ember"][0], sw=3.5)
        s.path("M64,58 Q76,76 70,90 Q64,94 58,90 Q52,76 64,58 Z", P["ember"][1], stroke="none", sw=0)
    return s


def app_icon():
    s = Svg(192, 192)
    s.rect(4, 4, 184, 184, P["red"][0], sw=6, rx=36)
    s.circle(96, 92, 66, P["red"][1], stroke="none", sw=0, opacity=0.5)
    s.path("M24,150 Q96,96 168,150", "none", stroke=INK, sw=14)
    s.path("M24,150 Q96,96 168,150", "none", stroke=P["stone"][1], sw=8)
    for x in (54, 96, 138):
        s.line(x, 150 - (40 if x == 96 else 26), x, 160, stroke=P["stone"][0], sw=6)
    s.rect(70, 70, 52, 40, P["wall"][0], sw=5)
    onion(s, 96, 70, 20, color="gold")
    return s


# --- Village interior: buildings and fields in three stages --------------------
# Stage 1: levels 1-3, stage 2: 4-7, stage 3: 8 and up (client Art.building_id).

def plot_ground(s):
    s.ellipse(64, 104, 56, 18, P["mud"][0] if False else "#8a7a5a", stroke="none", sw=0, opacity=0.55)


def stone_base(s, x0, x1, y, h=10):
    s.rect(x0, y - h, x1 - x0, h, P["stone"][0], sw=3)
    for x in range(int(x0) + 10, int(x1), 14):
        s.line(x, y - h, x, y, sw=1.5, opacity=0.5)


def sign(s, x, y, color="red", emblem=None):
    s.rect(x - 11, y - 11, 22, 22, P[color][0], sw=2.5, rx=3)
    if emblem == "spears":
        s.line(x - 7, y + 7, x + 7, y - 7, sw=2.5)
        s.line(x + 7, y + 7, x - 7, y - 7, sw=2.5)
    elif emblem == "scroll":
        s.rect(x - 7, y - 5, 14, 10, P["bone"][0], sw=2)
    elif emblem == "sheaf":
        s.line(x, y + 7, x - 5, y - 6, stroke=P["thatch"][1], sw=2.5)
        s.line(x, y + 7, x, y - 7, stroke=P["thatch"][1], sw=2.5)
        s.line(x, y + 7, x + 5, y - 6, stroke=P["thatch"][1], sw=2.5)


def cart(s, x, y, w=34, covered=False):
    if covered:
        s.path(f"M{x - w / 2},{y - 10} Q{x},{y - 34} {x + w / 2},{y - 10} Z", P["cloth"][0], sw=3)
    s.rect(x - w / 2, y - 12, w, 10, P["wood"][0], sw=3)
    for dx in (-w / 3, w / 3):
        s.circle(x + dx, y, 6, P["wood"][1], sw=2.5)


def building(kind, stage):
    s = Svg()
    plot_ground(s)
    s.shadow(64, 110, 50, 10)
    big = [0, 0.8, 0.95, 1.08][stage]
    if kind == "elder_hall":
        if stage == 3:
            stone_base(s, 14, 114, 112)
        hall(s, 64, 112 - (10 if stage == 3 else 0), 74 * big)
        if stage >= 2:
            s.line(100, 98, 100, 46, sw=3)
            s.poly([(100, 46), (118, 52), (100, 58)], P["red"][0], sw=2.5)
        if stage == 3:
            onion(s, 64, 50, 8)
    elif kind == "storehouse":
        w = 70 * big
        s.rect(64 - w / 2, 112 - w * 0.55, w, w * 0.55, P["wood"][0], sw=3.5)
        s.poly([(64 - w * 0.6, 112 - w * 0.55), (64, 112 - w * 1.05), (64 + w * 0.6, 112 - w * 0.55)], P["thatch" if stage < 3 else "roof"][0], sw=3.5)
        s.rect(52, 84, 24, 28, P["wood"][1], sw=3)
        s.line(52, 84, 76, 112, sw=2)
        s.line(76, 84, 52, 112, sw=2)
        for i in range(stage):
            s.ellipse(22 + i * 10, 108, 8, 6, P["bone"][0], sw=2.5)
    elif kind == "barracks":
        if stage == 1:
            for x in (40, 84):
                s.poly([(x - 22, 110), (x, 70), (x + 22, 110)], P["sand"][0], sw=3.5)
                s.poly([(x - 4, 110), (x, 96), (x + 4, 110)], INK, sw=0)
        else:
            w = 80 * big
            s.rect(64 - w / 2, 112 - 32, w, 32, P["wood" if stage == 2 else "stone"][0], sw=3.5)
            s.poly([(64 - w * 0.55, 80), (64, 52), (64 + w * 0.55, 80)], P["roof"][0], sw=3.5)
            s.rect(56, 92, 16, 20, INK, sw=0)
            if stage == 3:
                tower(s, 112, 112, 16, 54)
        sign(s, 64, 66 if stage > 1 else 56, "red", "spears")
    elif kind == "scout_lodge":
        h = [0, 34, 46, 56][stage]
        for x in (50, 78):
            s.line(x, 112, x + (8 if x < 64 else -8), 112 - h, stroke=P["wood"][0], sw=6)
        s.line(52, 112 - h * 0.4, 76, 112 - h * 0.6, stroke=P["wood"][1], sw=3)
        s.rect(46, 112 - h - 14, 36, 14, P["wood"][1], sw=3)
        s.poly([(42, 112 - h - 14), (64, 112 - h - 34), (86, 112 - h - 14)], P["thatch"][0], sw=3)
        if stage == 3:
            s.line(64, 112 - h - 34, 64, 112 - h - 52, sw=2.5)
            s.poly([(64, 112 - h - 52), (80, 112 - h - 47), (64, 112 - h - 42)], P["red"][0], sw=2)
    elif kind == "caravan_yard":
        s.rect(14, 74, 48, 38, P["wood"][0], sw=3.5)
        s.poly([(10, 74), (38, 54), (66, 74)], P["thatch"][0], sw=3.5)
        for i in range(stage):
            cart(s, 84, 112 - i * 14, covered=i == stage - 1)
    elif kind == "settlers_lodge":
        hut(s, 46, 112, 44 * big)
        cart(s, 92, 112, covered=True)
        if stage >= 2:
            s.circle(92, 72, 4, P["thatch"][1], sw=2)
        if stage == 3:
            hut(s, 96, 84, 24)
    elif kind == "academy":
        w = 72 * big
        s.rect(64 - w / 2, 112 - 40, w, 40, P["wall"][0], sw=3.5)
        s.poly([(64 - w * 0.58, 72), (64, 44), (64 + w * 0.58, 72)], P["roof"][0], sw=3.5)
        for x in (44, 84):
            s.rect(x - 5, 84, 10, 14, P["water"][0], sw=2)
        sign(s, 64, 96, "wood", "scroll")
        if stage == 3:
            onion(s, 64, 44, 9, color="water")
    elif kind == "granary_temple":
        w = 74 * big
        stone_base(s, 64 - w / 2, 64 + w / 2, 112)
        s.rect(64 - w / 2 + 6, 70, w - 12, 32, P["wood"][1], sw=3.5)
        s.poly([(64 - w * 0.58, 70), (64, 34), (64 + w * 0.58, 70)], P["thatch"][0], sw=3.5)
        sign(s, 64, 86, "gold", "sheaf")
        if stage >= 2:
            onion(s, 64, 34, 6)
    elif kind == "stone_redoubt":
        w = 80 * big
        s.rect(64 - w / 2, 70, w, 42, P["stone"][0], sw=4)
        for i in range(6):
            s.rect(64 - w / 2 + i * w / 6, 62, w / 12, 8, P["stone"][0], sw=2.5)
        s.path("M54,112 L54,94 Q64,84 74,94 L74,112 Z", INK, sw=0)
        if stage >= 2:
            tower(s, 64 - w / 2, 112, 18, 58)
        if stage == 3:
            tower(s, 64 + w / 2, 112, 18, 58)
    elif kind == "longhouse_hall":
        w = 104 * big
        s.rect(64 - w / 2, 84, w, 28, P["wood"][0], sw=3.5)
        s.path(f"M{64 - w / 2 - 4},84 Q64,{54 - stage * 4} {64 + w / 2 + 4},84 Z", P["thatch"][0], sw=3.5)
        s.rect(58, 94, 12, 18, INK, sw=0)
        for i in range(stage):
            s.circle(64 - w / 3 + i * w / 3, 98, 4, P["gold"][0], sw=2)
    return s


def field(kind, stage):
    s = Svg()
    s.ellipse(64, 72, 56, 50, {"woodcutter": P["grass"][0], "quarry": P["hill"][0], "farm": P["meadow"][0], "iron_mine": P["rock"][0]}[kind], sw=4)
    if kind == "woodcutter":
        for x, y in [(36, 66), (64, 54), (92, 66)][: stage + 0]:
            tree(s, x, y, 30 + stage * 3)
        for i in range(stage):
            s.rect(40 + i * 8, 96 - i * 6, 46, 10, P["wood"][0], sw=2.5, rx=5)
        s.ellipse(92, 100, 9, 5, P["wood"][1], sw=2.5)
    elif kind == "quarry":
        s.path("M24,98 L36,66 L58,58 L70,80 L60,100 Z", P["rock"][0], sw=3)
        for i in range(stage):
            s.rect(70 + (i % 2) * 14, 92 - (i // 2) * 12 - i * 4, 18, 12, P["stone"][1], sw=2.5)
        if stage == 3:
            s.line(96, 100, 96, 44, stroke=P["wood"][0], sw=4)
            s.line(96, 44, 70, 52, stroke=P["wood"][0], sw=3)
            s.line(72, 52, 72, 66, sw=1.5)
    elif kind == "farm":
        rows = stage + 1
        for i in range(rows):
            y = 52 + i * (52 / rows)
            s.line(24, y, 104, y, stroke=P["thatch"][1], sw=5)
            s.line(24, y, 104, y, stroke=P["thatch"][0], sw=2)
        if stage >= 2:
            s.rect(84, 84, 20, 22, P["wood"][1], sw=2.5)
            s.poly([(80, 84), (94, 72), (108, 84)], P["thatch"][0], sw=2.5)
    else:  # iron_mine
        s.path("M34,100 Q36,56 64,52 Q92,56 94,100 Z", P["rock"][1], sw=3.5)
        s.path("M48,100 Q50,72 64,70 Q78,72 80,100 Z", INK, sw=0)
        s.line(48, 72, 80, 72, stroke=P["wood"][0], sw=5)
        if stage >= 2:
            s.rect(84, 90, 22, 12, P["iron"][0], sw=2.5)
            s.circle(88, 104, 4, P["wood"][1], sw=2)
            s.circle(102, 104, 4, P["wood"][1], sw=2)
        if stage == 3:
            s.rect(18, 70, 16, 30, P["stone"][0], sw=2.5)
            s.circle(26, 60, 7, "#6d655a", stroke="none", sw=0, opacity=0.6)
            s.circle(26, 64, 4, P["ember"][1], sw=1.5)
    return s


def plot(kind):
    s = Svg()
    if kind == "empty":
        s.ellipse(64, 84, 54, 30, "#8a7a5a", sw=3)
        for x, y in [(18, 84), (110, 84), (64, 56), (64, 112)]:
            s.line(x, y, x, y - 14, stroke=P["wood"][0], sw=4)
        s.line(18, 76, 64, 50, stroke=P["cloth"][0], sw=1.5, opacity=0.8)
        s.line(64, 50, 110, 76, stroke=P["cloth"][0], sw=1.5, opacity=0.8)
    else:  # locked: dark, bramble-grown ground under a padlock
        s.ellipse(64, 84, 54, 30, "#5a4e3c", sw=3)
        for x, y in [(30, 86), (98, 86), (48, 102), (82, 102)]:
            tuft(s, x, y, color="#3d4a26", size=9)
        s.path("M 54 66 L 54 56 A 10 10 0 0 1 74 56 L 74 66", fill="none", stroke=INK, sw=4)
        s.rect(48, 64, 32, 24, "#8f8678", sw=3)
        s.circle(64, 74, 3.5, INK, stroke="none", sw=0)
        s.line(64, 76, 64, 82, stroke=INK, sw=3)
    return s


VILLAGE_BUILDINGS = ["elder_hall", "storehouse", "barracks", "scout_lodge", "caravan_yard", "settlers_lodge", "academy", "granary_temple", "stone_redoubt", "longhouse_hall"]
FIELDS = ["woodcutter", "quarry", "farm", "iron_mine"]


# --- Interface: frames, buttons and icons ---------------------------------------
# Frames and buttons are nine-sliced by the client (UiTheme): the corners keep
# their size, the edges and middle stretch, so nothing but the corners may
# change along an edge.
PANEL_BG = "#2a221b"
PANEL_WOOD = ("#5a3a20", "#7a5230")
TRIM = "#c9a13f"


def ornament(s, x, y, r):
    """A small carved rosette: a gold rhombus with a red heart."""
    s.poly([(x, y - r), (x + r, y), (x, y + r), (x - r, y)], P["gold"][0], sw=2)
    s.poly([(x, y - r * 0.45), (x + r * 0.45, y), (x, y + r * 0.45), (x - r * 0.45, y)], P["red"][0], stroke="none", sw=0)


def ui_panel():
    s = Svg(96, 96)
    s.rect(2, 2, 92, 92, PANEL_WOOD[0], sw=3, rx=12)
    s.line(14, 5.5, 82, 5.5, stroke=PANEL_WOOD[1], sw=2)
    s.rect(9, 9, 78, 78, PANEL_BG, sw=2, rx=6)
    s.rect(12.5, 12.5, 71, 71, "none", stroke=TRIM, sw=1.5, rx=4, opacity=0.8)
    for x in (9, 87):
        for y in (9, 87):
            ornament(s, x, y, 7)
    return s


def ui_field():
    s = Svg(48, 48)
    s.rect(2, 2, 44, 44, "#1d1712", sw=3, rx=8)
    s.rect(5.5, 5.5, 37, 37, "none", stroke=PANEL_WOOD[1], sw=1.5, rx=5)
    return s


BUTTON_LOOKS = {
    "button": (P["wood"][0], P["wood"][1], "#6b4220"),
    "button_hover": ("#a06a37", "#c48b55", "#7a4c26"),
    "button_pressed": ("#6f4622", "#5a381b", "#8b5a2b"),
    "button_disabled": ("#5b5048", "#6e625a", "#4a4039"),
}


def ui_button(look):
    s = Svg(64, 64)
    if look == "button_selected":
        # The open tab: dark like the panel, trimmed in gold.
        s.rect(2, 2, 60, 60, PANEL_BG, stroke=P["gold"][0], sw=3, rx=10)
        s.rect(6, 54, 52, 4, P["gold"][0], stroke="none", sw=0, rx=2)
        return s
    base, light, dark = BUTTON_LOOKS[look]
    s.rect(2, 2, 60, 60, base, sw=3, rx=10)
    top, bottom = (light, dark) if look != "button_pressed" else (dark, light)
    s.rect(7, 6, 50, 7, top, stroke="none", sw=0, rx=3.5, opacity=0.8)
    s.rect(7, 51, 50, 7, bottom, stroke="none", sw=0, rx=3.5, opacity=0.8)
    return s


def ui_divider():
    s = Svg(256, 24)
    for x0, x1 in [(8, 108), (148, 248)]:
        s.line(x0, 12, x1, 12, stroke=TRIM, sw=2.5)
    for x in (100, 156):
        s.circle(x, 12, 3, P["gold"][0], sw=1.5)
    ornament(s, 128, 12, 10)
    return s


def icon(kind):
    s = Svg(64, 64)
    if kind == "back":
        s.path("M40,10 L18,32 L40,54", "none", stroke=INK, sw=12)
        s.path("M40,10 L18,32 L40,54", "none", stroke=P["gold"][0], sw=6)
    elif kind == "map":
        s.poly([(6, 14), (22, 8), (42, 14), (58, 8), (58, 50), (42, 56), (22, 50), (6, 56)], P["bone"][0], sw=3)
        s.line(22, 8, 22, 50, sw=2)
        s.line(42, 14, 42, 56, sw=2)
        s.path("M12,44 Q22,30 32,36 T50,22", "none", stroke=P["red"][0], sw=3)
        s.path("M46,18 L54,26 M54,18 L46,26", "none", stroke=P["red"][0], sw=3.5)
    elif kind == "village":
        s.shadow(32, 54, 26, 5)
        hut(s, 22, 52, 24)
        hut(s, 42, 54, 28, roof="roof")
    elif kind == "inbox":
        s.rect(10, 12, 44, 40, P["bone"][0], sw=3, rx=4)
        s.path("M10,16 L32,34 L54,16", "none", sw=3)
        s.circle(32, 40, 8, P["red"][0], sw=2.5)
    elif kind == "threat":
        # A war horn.
        s.path("M8,40 Q20,12 52,10 L56,24 Q30,24 20,48 Z", P["bone"][0], sw=3)
        s.path("M52,10 L56,24", "none", stroke=P["iron"][0], sw=5)
        s.line(14, 46, 22, 52, stroke=P["wood"][0], sw=6)
    elif kind == "build":
        s.line(10, 58, 38, 26, stroke=INK, sw=13)
        s.line(10, 58, 38, 26, stroke=P["wood"][0], sw=7)
        s.poly([(22, 18), (44, 4), (60, 26), (38, 40)], P["iron"][0], sw=3.5)
        s.line(28, 18, 44, 8, stroke=P["iron"][1], sw=3)
    elif kind == "troops":
        s.line(48, 6, 20, 58, stroke=P["wood"][0], sw=5)
        s.poly([(48, 4), (54, 10), (46, 16)], P["iron"][1], sw=2.5)
        s.path("M14,16 L44,16 L44,34 Q44,50 29,58 Q14,50 14,34 Z", P["red"][0], sw=3)
        s.path("M29,20 L29,52 M18,32 L40,32", "none", stroke=P["gold"][0], sw=3)
    elif kind == "caravan":
        s.shadow(32, 54, 26, 5)
        cart(s, 32, 50, w=44, covered=True)
    elif kind == "research":
        s.path("M6,18 Q20,12 32,18 Q44,12 58,18 L58,52 Q44,46 32,52 Q20,46 6,52 Z", P["bone"][0], sw=3)
        s.line(32, 18, 32, 52, sw=2)
        for y in (26, 33, 40):
            s.line(12, y, 26, y - 2, stroke=P["wood"][0], sw=2)
            s.line(38, y - 2, 52, y, stroke=P["wood"][0], sw=2)
    elif kind == "clock":
        s.circle(32, 32, 24, P["bone"][0], sw=3)
        s.path("M32,16 L32,32 L44,38", "none", sw=4)
    return s


def ui_title():
    """The start screen's picture: the Holy City over the river and the
    Kalinov Bridge, between forests."""
    s = Svg(360, 180)
    s.rect(0, 0, 360, 180, "#cfe0dc", stroke="none", sw=0)
    s.circle(292, 40, 22, P["gold"][1], stroke="none", sw=0, opacity=0.7)
    s.path("M0,100 Q60,60 130,86 Q200,52 260,80 Q320,58 360,84 L360,180 L0,180 Z", P["hill"][1], sw=3)
    s.path("M0,124 Q90,92 180,108 Q270,90 360,118 L360,180 L0,180 Z", P["grass"][0], sw=3)
    s.embed(holy_city(), 128, 22, 0.65)
    for x, y, size in [(22, 128, 26), (46, 136, 30), (14, 150, 28), (318, 124, 26), (342, 138, 30), (300, 148, 26)]:
        tree(s, x, y, size)
    s.path("M0,160 Q100,146 180,156 Q260,166 360,150 L360,180 L0,180 Z", P["water"][0], sw=3)
    s.path("M30,170 Q60,164 90,170 M220,168 Q250,162 280,168", "none", stroke="#ffffff", sw=2, opacity=0.7)
    s.path("M120,160 Q180,122 240,160", "none", stroke=INK, sw=12)
    s.path("M120,160 Q180,122 240,160", "none", stroke=P["stone"][1], sw=7)
    for x in (150, 180, 210):
        s.line(x, 160 - (24 if x == 180 else 16), x, 168, stroke=P["stone"][0], sw=4)
    s.rect(1.5, 1.5, 357, 177, "none", sw=3)
    return s


UI_ICONS = ["back", "map", "village", "inbox", "threat", "build", "troops", "caravan", "research", "clock"]


# --- Build everything --------------------------------------------------------

def assets():
    out = {}
    for tid, (base, motif) in TERRAIN.items():
        out[f"terrain/{tid}"] = terrain(base, motif)
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
    for kind in ["wood", "stone", "grain", "iron", "ember"]:
        out[f"resource/{kind}"] = resource(kind)
    out["app/icon"] = app_icon()
    for kind in VILLAGE_BUILDINGS:
        for stage in (1, 2, 3):
            out[f"building/{kind}_{stage}"] = building(kind, stage)
    for kind in FIELDS:
        for stage in (1, 2, 3):
            out[f"field/{kind}_{stage}"] = field(kind, stage)
    out["plot/empty"] = plot("empty")
    out["plot/locked"] = plot("locked")
    out["ui/panel"] = ui_panel()
    out["ui/field"] = ui_field()
    for look in [*BUTTON_LOOKS, "button_selected"]:
        out[f"ui/{look}"] = ui_button(look)
    out["ui/divider"] = ui_divider()
    out["ui/title"] = ui_title()
    for kind in UI_ICONS:
        out[f"icon/{kind}"] = icon(kind)
    return out


def set_import_scale(svg_path):
    """Godot reads its import settings from <file>.import; a minimal one is
    completed by Godot on the next import."""
    imp = svg_path.with_name(svg_path.name + ".import")
    if not imp.exists():
        imp.write_text(f'[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\nsvg/scale={IMPORT_SCALE}\n')
        return
    lines = imp.read_text().splitlines()
    lines = [f"svg/scale={IMPORT_SCALE}" if line.startswith("svg/scale=") else line for line in lines]
    imp.write_text("\n".join(lines) + "\n")


def main():
    manifest = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}
    for art_id, svg in assets().items():
        path = OUT_DIR / f"{art_id}.svg"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(svg.text())
        set_import_scale(path)
        res = f"{RES}/{art_id}.svg"
        # Your own art (a path outside generated/) is never replaced.
        if not manifest.get(art_id, res).startswith(RES):
            continue
        manifest[art_id] = res
    MANIFEST.write_text(json.dumps(dict(sorted(manifest.items())), indent=2) + "\n")
    print(f"{len(manifest)} art ids in {MANIFEST.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
