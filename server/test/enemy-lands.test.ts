import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { bandOf, enemyLands, enemyRings, sightOf, withEnemyLands } from '../src/sim/enemyLands.js';
import { hex, hexDistance, hexKey, neighbors } from '../src/sim/hex.js';
import { frontOf } from '../src/sim/mapgen.js';

const data = loadGameData();

describe('enemy lands', () => {
  it('reach four bands past the edge, band by band', () => {
    expect(data.enemyLands.bands.map((b) => b.rings)).toEqual([3, 2, 3, 2]);
    expect(enemyRings(data)).toBe(10);
    expect(bandOf(data, hex(10, 0), 10)).toBe(0);
    expect(bandOf(data, hex(11, 0), 10)).toBe(1);
    expect(bandOf(data, hex(13, 0), 10)).toBe(1);
    expect(bandOf(data, hex(14, 0), 10)).toBe(2);
    expect(bandOf(data, hex(16, 0), 10)).toBe(3);
    expect(bandOf(data, hex(19, 0), 10)).toBe(4);
    expect(bandOf(data, hex(20, 0), 10)).toBe(4);
    expect(bandOf(data, hex(21, 0), 10)).toBeNull();
  });

  it('lie only on the sides of the active fronts, the same for a seed', () => {
    const lands = enemyLands(data, 99, 10, ['north', 'south']);
    expect(lands.length).toBeGreaterThan(0);
    for (const e of lands) {
      expect(['north', 'south']).toContain(e.front);
      expect(frontOf(e.cell)).toBe(e.front);
      const d = hexDistance(e.cell, hex(0, 0));
      expect(d).toBeGreaterThan(10);
      expect(d).toBeLessThanOrEqual(20);
      expect(data.terrain.terrain[e.terrain].settleable).toBe(false);
    }
    // North and South never touch: no rift between them.
    expect(lands.some((e) => e.terrain === 'rift')).toBe(false);
    expect(enemyLands(data, 99, 10, ['north', 'south'])).toEqual(lands);
  });

  it('keep two fronts apart with a rift where they meet', () => {
    const lands = enemyLands(data, 7, 12, ['north', 'east', 'south', 'west']);
    const byKey = new Map(lands.map((e) => [hexKey(e.cell), e]));
    // No step leads from one front's passable land into another's.
    for (const e of lands) {
      if (data.terrain.terrain[e.terrain].moveCost === null) continue;
      for (const n of neighbors(e.cell)) {
        const other = byKey.get(hexKey(n));
        if (other && other.front !== e.front) expect(data.terrain.terrain[other.terrain].moveCost).toBeNull();
      }
    }
    expect(lands.filter((e) => e.terrain === 'rift').length).toBeGreaterThan(0);
  });

  it('paint each front from its own palette', () => {
    const lands = enemyLands(data, 7, 12, ['north', 'east', 'south', 'west']);
    for (const e of lands) {
      if (e.terrain === 'rift') continue;
      expect(data.enemyLands.fronts[e.front]!.palette.map((p) => p.terrain)).toContain(e.terrain);
    }
  });

  it('are walked by armies, and seen band by band', () => {
    const world = { seed: 99, radius: 10, activeFronts: ['north', 'south'] };
    const land = withEnemyLands(data, new Map(), world);
    expect(land.size).toBe(enemyLands(data, 99, 10, ['north', 'south']).length);
    expect(sightOf(data, { enemySight: {} }, 'north')).toBe(1);
    expect(sightOf(data, { enemySight: { north: 3 } }, 'north')).toBe(3);
    expect(sightOf(data, { enemySight: { north: 9 } }, 'north')).toBe(4);
  });
});
