import { describe, expect, it } from 'vitest';
import { loadGameData, type TerrainId } from '../src/data/index.js';
import { hex } from '../src/sim/hex.js';
import { edgeKey, landOf, moveCostOn } from '../src/sim/land.js';
import { routeFrom } from '../src/sim/waves.js';

const data = loadGameData();

// A strip of plains q = 0..6 on r = 0.
function strip(): Map<string, TerrainId> {
  return new Map(Array.from({ length: 7 }, (_, q) => [`${q},0`, 'plains' as TerrainId]));
}

describe('land', () => {
  it('blocks river edges and makes roads cheaper, the more so the better the road', () => {
    const land = landOf(strip(), [edgeKey(hex(2, 0), hex(3, 0))], [[edgeKey(hex(0, 0), hex(1, 0)), 1], [edgeKey(hex(4, 0), hex(5, 0)), 3]]);
    const cost = moveCostOn(data, land);
    const [first, , third] = data.field.road.levels;
    expect(cost(hex(0, 0), hex(1, 0))).toBe(first!.factor);
    expect(cost(hex(1, 0), hex(0, 0))).toBe(first!.factor);
    expect(cost(hex(4, 0), hex(5, 0))).toBe(third!.factor);
    expect(third!.factor).toBeLessThan(data.field.road.levels[1]!.factor);
    expect(data.field.road.levels[1]!.factor).toBeLessThan(first!.factor);
    expect(cost(hex(1, 0), hex(2, 0))).toBe(1);
    expect(cost(hex(3, 0), hex(2, 0))).toBeNull();
    expect(moveCostOn(data, land, false)(hex(0, 0), hex(1, 0))).toBe(1);
  });

  it('lets human hordes take the roads, but not the Monsters of the North', () => {
    const land = landOf(strip(), [], [0, 1, 2, 3, 4, 5].map((q) => [edgeKey(hex(q, 0), hex(q + 1, 0)), 1] as const));
    const route = (front: 'north' | 'east') =>
      routeFrom(data, {
        terrain: land,
        from: hex(6, 0),
        targets: [{ id: 1, cell: hex(0, 0) }],
        front,
        composition: { [Object.keys(data.enemies.fronts[front]!.units)[0]!]: 10 },
        rng: () => 0,
        startMs: 0,
        worldSpeed: 1,
      })!;
    const unit = (front: 'north' | 'east') => data.enemies.fronts[front]!.units[Object.keys(data.enemies.fronts[front]!.units)[0]!]!;
    // Hours per hex at each faction's pace: halved on the road for the East only.
    expect(route('east').arrivesMs).toBe(Math.round((6 * data.field.road.levels[0]!.factor * 3_600_000) / unit('east').speed));
    expect(route('north').arrivesMs).toBe(Math.round((6 * 3_600_000) / unit('north').speed));
  });
});
