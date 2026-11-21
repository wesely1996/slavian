// Making lakes and digging rivers (field.json terraform flood, river):
// rivers run on from rivers, and nothing may cut a village off.
import { describe, expect, it } from 'vitest';
import { loadGameData, type TerrainId } from '../src/data/index.js';
import { reshapeProblem } from '../src/scheduler/terraform.js';
import { hex, hexKey, spiral } from '../src/sim/hex.js';
import { edgesMeet, landOf } from '../src/sim/land.js';

const data = loadGameData();

describe('reshaping the land', () => {
  // A narrow neck: the village at (3, 0) joined to the rest only through (2, 0).
  const terrain = new Map(spiral(hex(0, 0), 4).map((c) => [hexKey(c), (c.q === 0 && c.r === 0 ? 'holy_city' : 'plains') as TerrainId]));
  for (const c of spiral(hex(3, 0), 1)) if (hexKey(c) !== '3,0' && hexKey(c) !== '2,0') terrain.set(hexKey(c), 'mountain');
  const land = landOf(terrain, []);
  const base = { toward: null, land, rivers: [], villages: [hex(3, 0)] };

  it("won't flood the only way to a village", () => {
    expect(reshapeProblem(data, { ...base, action: 'flood', cell: hex(2, 0) })).toMatch(/cut a village off/);
    expect(reshapeProblem(data, { ...base, action: 'flood', cell: hex(-2, 0) })).toBe('');
    expect(reshapeProblem(data, { ...base, action: 'soak', cell: hex(2, 0) })).toBe('');
  });

  it('digs rivers on from rivers, between land', () => {
    const rivers = [{ a: hex(-2, 0), b: hex(-2, 1) }];
    const dig = (cell: { q: number; r: number }, toward: { q: number; r: number } | null) => reshapeProblem(data, { ...base, rivers, action: 'river', cell, toward });
    expect(dig(hex(-2, 0), null)).toMatch(/neighbouring hex/);
    expect(dig(hex(-2, 0), hex(-1, 0))).toBe('');
    expect(dig(hex(-2, 0), hex(-2, 1))).toMatch(/already/);
    expect(dig(hex(1, -2), hex(1, -1))).toMatch(/on from a river/);
    // Nor across the neck.
    expect(reshapeProblem(data, { ...base, rivers: [{ a: hex(2, 0), b: hex(3, -1) }], action: 'river', cell: hex(2, 0), toward: hex(3, 0) })).toMatch(/cut a village off/);
  });

  it('knows which edges meet at a corner', () => {
    expect(edgesMeet(hex(0, 0), hex(1, 0), hex(0, 0), hex(1, -1))).toBe(true);
    expect(edgesMeet(hex(0, 0), hex(1, 0), hex(0, 0), hex(-1, 0))).toBe(false);
  });
});
