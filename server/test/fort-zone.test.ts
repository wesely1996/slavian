// A fort an army holds has a zone of control (field.json fort.zoneDetour):
// hordes keep two hexes away from it, or march on it first when going
// round costs too much.
import { describe, expect, it } from 'vitest';
import { loadGameData, type TerrainId } from '../src/data/index.js';
import { hex, hexDistance, hexKey, spiral } from '../src/sim/hex.js';
import { landOf } from '../src/sim/land.js';
import { routeFrom } from '../src/sim/waves.js';

const data = loadGameData();

function route(terrain: Map<string, TerrainId>, forts: string[]) {
  return routeFrom(data, {
    terrain: landOf(terrain, [], [], [], [], [], forts),
    from: hex(0, -6),
    targets: [{ id: 1, cell: hex(0, 6) }],
    front: 'south',
    composition: { zealot: 10 },
    rng: () => 0,
    startMs: 0,
    worldSpeed: 1,
  })!.path.map((s) => hex(s.q, s.r));
}

describe('fort zone of control', () => {
  const open = new Map(spiral(hex(0, 0), 8).map((c) => [hexKey(c), 'plains' as TerrainId]));

  it('keeps hordes two hexes away from a held fort', () => {
    const path = route(open, ['0,0']);
    expect(path.at(-1)).toEqual(hex(0, 6));
    expect(path.every((c) => hexDistance(c, hex(0, 0)) >= 2)).toBe(true);
    // Without the fort it marches straight past.
    expect(route(open, []).some((c) => hexDistance(c, hex(0, 0)) <= 1)).toBe(true);
  });

  it('marches on the fort first when the way round is too long', () => {
    // A wall of mountains with one gap, the fort in it: round is far.
    const walled = new Map(open);
    for (let q = -8; q <= 8; q++) if (q !== 0) walled.set(hexKey(hex(q, 0)), 'mountain');
    const path = route(walled, ['0,0']);
    expect(path.some((c) => c.q === 0 && c.r === 0)).toBe(true);
    expect(path.at(-1)).toEqual(hex(0, 6));
  });

  it('lets a horde already beside a fort move on', () => {
    const path = routeFrom(data, {
      terrain: landOf(open, [], [], [], [], [], ['0,-5']),
      from: hex(0, -6),
      targets: [{ id: 1, cell: hex(0, 6) }],
      front: 'south',
      composition: { zealot: 10 },
      rng: () => 0,
      startMs: 0,
      worldSpeed: 1,
    });
    expect(path).not.toBeNull();
  });
});
