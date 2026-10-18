import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { DATA_DIR } from '../src/data/index.js';
import {
  DIRECTIONS,
  findPath,
  hex,
  hexDistance,
  hexKey,
  hexRound,
  hexToPixel,
  neighbors,
  pixelToHex,
  ring,
  spiral,
  type Hex,
} from '../src/sim/hex.js';

type Pair = [number, number];
const vectors = JSON.parse(readFileSync(`${DATA_DIR}/fixtures/hex-vectors.json`, 'utf8')) as {
  directions: Pair[];
  distance: [Pair, Pair, number][];
  ringCounts: Pair[];
  spiralCounts: Pair[];
  toPixel: [Pair, number, Pair][];
  round: [Pair, Pair][];
};
const h = ([q, r]: Pair): Hex => hex(q, r);

describe('hex math (shared vectors)', () => {
  it('uses the shared direction order', () => {
    expect(DIRECTIONS.map((d) => [d.q, d.r])).toEqual(vectors.directions);
  });

  it.each(vectors.distance)('distance %j -> %j = %i', (a, b, expected) => {
    expect(hexDistance(h(a), h(b))).toBe(expected);
    expect(hexDistance(h(b), h(a))).toBe(expected);
  });

  it.each(vectors.ringCounts)('ring radius %i has %i hexes', (radius, count) => {
    const cells = ring(hex(0, 0), radius);
    expect(cells).toHaveLength(count);
    expect(new Set(cells.map(hexKey)).size).toBe(count);
    for (const cell of cells) expect(hexDistance(cell, hex(0, 0))).toBe(radius);
  });

  it.each(vectors.spiralCounts)('spiral radius %i has %i hexes', (radius, count) => {
    expect(new Set(spiral(hex(0, 0), radius).map(hexKey)).size).toBe(count);
  });

  it.each(vectors.toPixel)('pixel of %j at size %d', (cell, size, [x, y]) => {
    const p = hexToPixel(h(cell), size);
    expect(p.x).toBeCloseTo(x, 5);
    expect(p.y).toBeCloseTo(y, 5);
  });

  it.each(vectors.round)('rounds %j to %j', ([q, r], expected) => {
    expect(hexRound(q, r)).toEqual(h(expected));
  });
});

describe('hex math', () => {
  it('round-trips hex -> pixel -> hex', () => {
    for (const cell of spiral(hex(0, 0), 6)) {
      expect(pixelToHex(hexToPixel(cell, 37), 37)).toEqual(cell);
    }
  });

  it('neighbours are all at distance 1', () => {
    for (const n of neighbors(hex(3, -2))) expect(hexDistance(n, hex(3, -2))).toBe(1);
  });

  it('normalises negative zero', () => {
    expect(hexKey(hex(-0, 0))).toBe('0,0');
  });
});

describe('findPath', () => {
  const inside = (radius: number) => (_: Hex, to: Hex) => (hexDistance(to, hex(0, 0)) <= radius ? 1 : null);

  it('finds a shortest path on open ground', () => {
    const path = findPath(hex(-3, 0), hex(3, 0), inside(5))!;
    expect(path[0]).toEqual(hex(-3, 0));
    expect(path.at(-1)).toEqual(hex(3, 0));
    expect(path).toHaveLength(7);
    for (let i = 1; i < path.length; i++) expect(hexDistance(path[i - 1]!, path[i]!)).toBe(1);
  });

  it('routes around a wall', () => {
    const wall = new Set(['0,-2', '0,-1', '0,0', '0,1', '0,2'].map(String));
    const cost = (_: Hex, to: Hex) =>
      hexDistance(to, hex(0, 0)) <= 4 && !wall.has(hexKey(to)) ? 1 : null;
    const path = findPath(hex(-2, 0), hex(2, 0), cost)!;
    expect(path.some((cell) => wall.has(hexKey(cell)))).toBe(false);
    expect(path.length).toBeGreaterThan(5);
  });

  it('prefers cheap terrain over a short expensive route', () => {
    // The direct row r = 0 is swamp (cost 10); going around is cheaper.
    const cost = (_: Hex, to: Hex) => (hexDistance(to, hex(0, 0)) > 4 ? null : to.r === 0 && to.q !== 2 ? 10 : 1);
    const path = findPath(hex(-2, 0), hex(2, 0), cost)!;
    expect(path.slice(1, -1).every((cell) => cell.r !== 0)).toBe(true);
  });

  it('returns null when the goal is unreachable', () => {
    expect(findPath(hex(0, 0), hex(9, 0), inside(3))).toBeNull();
  });
});
