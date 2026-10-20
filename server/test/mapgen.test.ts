import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { findPath, hex, hexDistance, hexKey, ring, spiral, type Hex } from '../src/sim/hex.js';
import { commonNeighbors, edgeKey, moveCostOn } from '../src/sim/land.js';
import { activeFrontsFor, frontOf, generateMap, landOfMap, radiusFor, START_RING, WATER } from '../src/sim/mapgen.js';

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

describe('rivers', () => {
  const maps = Array.from({ length: 20 }, (_, i) => generateMap(data, 1000 + i * 37, 1 + (i % 6)));

  it('run along edges between neighbouring hexes, never by the Holy City', () => {
    expect(maps.some((m) => m.rivers.length > 0)).toBe(true);
    for (const map of maps) {
      const keys = new Set<string>();
      for (const edge of map.rivers) {
        expect(hexDistance(edge.a, edge.b)).toBe(1);
        expect(map.terrain.get(hexKey(edge.a))).not.toBe('holy_city');
        expect(map.terrain.get(hexKey(edge.b))).not.toBe('holy_city');
        keys.add(edgeKey(edge.a, edge.b));
      }
      expect(keys.size).toBe(map.rivers.length);
    }
  });

  it('end in a lake, the ocean, off the map or another river; never along a shore', () => {
    for (const map of maps) {
      const type = (h: Hex) => map.terrain.get(hexKey(h));
      const corners = new Map<string, Hex[][]>();
      for (const edge of map.rivers) {
        // A river runs between two land hexes, so no bridge ever leads onto water.
        for (const end of [edge.a, edge.b]) expect(WATER).not.toContain(type(end));
        for (const third of commonNeighbors(edge.a, edge.b)) {
          const key = [edge.a, edge.b, third].map(hexKey).sort().join('/');
          corners.set(key, [...(corners.get(key) ?? []), [edge.a, edge.b, third]]);
        }
      }
      for (const meeting of corners.values()) {
        if (meeting.length !== 1) continue;
        // A loose end: where the river rises in the hills, or its mouth.
        const [a, b, third] = meeting[0]!;
        const rises = [a!, b!].some((h) => ['hills', 'mountain'].includes(type(h)!));
        const mouth = type(third!) === undefined || WATER.includes(type(third!)!);
        expect(rises || mouth).toBe(true);
      }
    }
    // Somewhere a river joins another, which runs on wider below.
    expect(maps.some((m) => m.rivers.some((e) => e.size > 1))).toBe(true);
  });

  it('can be crossed only at bridges, and every start and front still gets through', () => {
    for (const map of maps) {
      const land = landOfMap(map);
      const cost = moveCostOn(data, land);
      const blocked = map.rivers.find((e) => !e.bridge);
      if (blocked) expect(cost(blocked.a, blocked.b)).toBeNull();
      const passable = (h: { q: number; r: number }) => data.terrain.terrain[map.terrain.get(hexKey(h))!].moveCost !== null;
      const bridge = map.rivers.find((e) => e.bridge && passable(e.a) && passable(e.b));
      if (bridge) expect(cost(bridge.a, bridge.b)).not.toBeNull();
      for (const start of map.startSites) expect(findPath(start, hex(0, 0), cost)).not.toBeNull();
    }
    expect(maps.some((m) => m.rivers.some((e) => e.bridge)) && maps.some((m) => m.rivers.some((e) => !e.bridge))).toBe(true);
  });
});
