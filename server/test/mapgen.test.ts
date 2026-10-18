import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { hex, hexDistance, hexKey, ring, spiral } from '../src/sim/hex.js';
import { activeFrontsFor, frontOf, generateMap, radiusFor, START_RING } from '../src/sim/mapgen.js';

const data = loadGameData();

describe('map generation', () => {
  it.each([1, 2, 3, 4, 5, 6])('builds a playable map for %i player(s)', (players) => {
    const map = generateMap(data, 12345, players);
    const radius = radiusFor(players);
    expect(map.radius).toBe(radius);
    expect(map.terrain.size).toBe(spiral(hex(0, 0), radius).length);
    expect(map.terrain.get('0,0')).toBe('holy_city');

    expect(map.startSites).toHaveLength(players);
    expect(new Set(map.startSites.map(hexKey)).size).toBe(players);
    for (const site of map.startSites) {
      expect(hexDistance(site, hex(0, 0))).toBe(START_RING);
      expect(data.terrain.terrain[map.terrain.get(hexKey(site))!].settleable).toBe(true);
    }

    // Edge hexes of inactive fronts are ocean; active fronts get spawn terrain.
    for (const cell of ring(hex(0, 0), radius)) {
      const isOcean = map.terrain.get(hexKey(cell)) === 'ocean';
      expect(isOcean).toBe(!map.activeFronts.includes(frontOf(cell)));
    }
  });

  it('activates fronts by group size', () => {
    expect(activeFrontsFor(1)).toEqual(['north', 'south']);
    expect(activeFrontsFor(2)).toEqual(['north', 'south', 'east']);
    expect(activeFrontsFor(3)).toHaveLength(4);
  });

  it('is deterministic for a seed', () => {
    const a = generateMap(data, 777, 4);
    const b = generateMap(data, 777, 4);
    expect([...a.terrain]).toEqual([...b.terrain]);
    expect(a.seed).toBe(b.seed);
  });

  it('produces varied interior terrain', () => {
    const types = new Set(generateMap(data, 4242, 6).terrain.values());
    for (const type of ['plains', 'forest', 'hills']) expect(types).toContain(type);
  });
});
