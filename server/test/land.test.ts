import { describe, expect, it } from 'vitest';
import { loadGameData, type TerrainId } from '../src/data/index.js';
import { hex } from '../src/sim/hex.js';
import { edgeKey, landOf, moveCostOn, riverLanes, roadLink } from '../src/sim/land.js';
import { routeFrom } from '../src/sim/waves.js';

const data = loadGameData();

// A strip of plains q = 0..6 on r = 0.
function strip(): Map<string, TerrainId> {
  return new Map(Array.from({ length: 7 }, (_, q) => [`${q},0`, 'plains' as TerrainId]));
}

describe('land', () => {
  it('sails a boat across a lake on its river, and up the rivers flowing into it', () => {
    const terrain = new Map<string, TerrainId>();
    for (let q = 0; q <= 7; q++) for (let r = -1; r <= 1; r++) terrain.set(`${q},${r}`, 'plains');
    terrain.set('3,0', 'lake');
    terrain.set('4,0', 'lake');
    // One river runs into the lake from the west, another leaves it to the east.
    const rivers = [{ a: hex(1, 0), b: hex(2, 0) }, { a: hex(5, 0), b: hex(6, 0) }];
    const plain = riverLanes(rivers, rivers[0]!);
    expect(plain).toEqual([edgeKey(hex(1, 0), hex(2, 0))]);
    const lanes = riverLanes(rivers, rivers[0]!, terrain);
    expect(lanes).toContain(edgeKey(hex(2, 0), hex(3, 0)));
    expect(lanes).toContain(edgeKey(hex(3, 0), hex(4, 0)));
    expect(lanes).toContain(edgeKey(hex(4, 0), hex(5, 0)));
    expect(lanes).toContain(edgeKey(hex(5, 0), hex(6, 0)));
    expect(lanes).not.toContain(edgeKey(hex(6, 0), hex(7, 0)));
    // Only a boat crosses the lake, at the lane's speed.
    const cost = moveCostOn(data, landOf(terrain, [], [], lanes));
    const shipyard = data.events.kinds.shipyard;
    expect(cost(hex(2, 0), hex(3, 0))).toBeCloseTo(shipyard.lakeMoveCost / shipyard.laneSpeed);
    expect(moveCostOn(data, landOf(terrain, []))(hex(2, 0), hex(3, 0))).toBeNull();
    expect(moveCostOn(data, landOf(terrain, [], [], lanes), false)(hex(2, 0), hex(3, 0))).toBeNull();
  });

  it('links an outpost to its village by the fewest road steps, averaging their bonus', () => {
    const v = hex(0, 0);
    const a = hex(1, 0);
    const b = hex(2, -1);
    const bonus = data.field.road.levels.map((l) => l.outpostBonus);
    // No road, or a road that stops short: no link.
    expect(roadLink(data, new Map(), b, v)).toBe(0);
    expect(roadLink(data, new Map([[edgeKey(v, a), 3]]), b, v)).toBe(0);
    // Two steps, levels 1 and 3: their average.
    const two = new Map([[edgeKey(v, a), 1], [edgeKey(a, b), 3]]);
    expect(roadLink(data, two, b, v)).toBeCloseTo((bonus[0]! + bonus[2]!) / 2);
    // A longer, better road round doesn't count over the shorter one ...
    const round = new Map([...two, [edgeKey(b, hex(2, 0)), 3], [edgeKey(hex(2, 0), hex(1, 1)), 3], [edgeKey(hex(1, 1), hex(0, 1)), 3], [edgeKey(hex(0, 1), v), 3]]);
    expect(roadLink(data, round, b, v)).toBeCloseTo((bonus[0]! + bonus[2]!) / 2);
    // ... but of two as short, the better built does.
    const twin = new Map([...two, [edgeKey(v, hex(1, -1)), 3], [edgeKey(hex(1, -1), b), 2]]);
    expect(roadLink(data, twin, b, v)).toBeCloseTo((bonus[2]! + bonus[1]!) / 2);
  });

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
