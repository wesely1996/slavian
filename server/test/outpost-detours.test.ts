// Hordes go out of their way through outposts worth it (horde.json outposts).
import { describe, expect, it } from 'vitest';
import { loadGameData, type TerrainId } from '../src/data/index.js';
import type { Front } from '../src/sim/mapgen.js';
import { hex, hexDistance, hexKey, spiral, type Hex } from '../src/sim/hex.js';
import { landOf } from '../src/sim/land.js';
import { routeFrom, type OutpostSite } from '../src/sim/waves.js';
import { outpostRecruits } from '../src/sim/horde.js';

const data = loadGameData();
const open = new Map(spiral(hex(0, 0), 8).map((c) => [hexKey(c), 'plains' as TerrainId]));

function road(outposts: OutpostSite[], front: Front = 'south', composition: Record<string, number> = { zealot: 10 }): Hex[] {
  return routeFrom(data, {
    terrain: landOf(open, [], [], [], [], [], []),
    from: hex(0, -6),
    targets: [{ id: 1, cell: hex(0, 6) }],
    front,
    composition,
    rng: () => 0,
    startMs: 0,
    worldSpeed: 1,
    outposts,
  })!.path.map((s) => hex(s.q, s.r));
}

const on = (path: Hex[], cell: Hex) => path.some((c) => c.q === cell.q && c.r === cell.r);

describe('outposts on a horde\'s road', () => {
  const straight = road([]);
  // Two hexes off the straight road: worth it at level 5, not at level 1.
  const aside = spiral(hex(0, 0), 3).find((c) => Math.min(...straight.map((s) => hexDistance(s, c))) === 2)!;

  it('goes out of its way for a rich outpost, not for a poor one', () => {
    expect(on(road([{ cell: aside, level: 5 }]), aside)).toBe(true);
    expect(on(road([{ cell: aside, level: 1 }]), aside)).toBe(false);
    expect(road([{ cell: aside, level: 5 }]).at(-1)).toEqual(hex(0, 6));
  });

  it('weighs them by its faction\'s greed', () => {
    // Level 1, two hexes off (two more hexes of plains): the nomads (x1.5,
    // worth 2.25) go, the Order (x0.8, worth 1.2) does not.
    expect(on(road([{ cell: aside, level: 1 }], 'east', { steppe_raider: 10 }), aside)).toBe(true);
    expect(on(road([{ cell: aside, level: 1 }]), aside)).toBe(false);
  });

  it('looks no further than its search reach', () => {
    const far = spiral(hex(0, 0), 8).find((c) => Math.min(...straight.map((s) => hexDistance(s, c))) === data.horde.outposts.searchReach + 1)!;
    expect(on(road([{ cell: far, level: 5 }]), far)).toBe(false);
  });

  it('swells with an outpost\'s supplies', () => {
    expect(outpostRecruits(data, { zealot: 50, crossbow: 10 }, { zealot: 40, crossbow: 10 }, 5)).toEqual({ zealot: 45, crossbow: 11 });
  });
});
