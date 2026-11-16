import { describe, expect, it } from 'vitest';
import { loadGameData, type TerrainId } from '../src/data/index.js';
import { planMapEvent } from '../src/sim/events.js';
import { hex, hexKey, type Hex } from '../src/sim/hex.js';
import { riverWater } from '../src/sim/land.js';
import { FRONTS } from '../src/sim/mapgen.js';

const data = loadGameData();

// A river zigzagging west to east along row `r`: every edge shares a bank
// hex with the next, so it is one river.
function river(r: number): { a: Hex; b: Hex }[] {
  const edges: { a: Hex; b: Hex }[] = [];
  for (let q = -8; q <= 8; q++) edges.push({ a: hex(q, r - 1), b: hex(q, r) }, { a: hex(q, r), b: hex(q + 1, r - 1) });
  return edges;
}

describe('map events', () => {
  it('raise one shipyard to a river: never on the banks of one that has a shipyard', () => {
    const terrain = new Map<string, TerrainId>();
    for (let q = -12; q <= 12; q++) for (let r = -12; r <= 12; r++) terrain.set(`${q},${r}`, 'plains');
    const north = river(-3);
    const south = river(5);
    const rivers = [...north, ...south];
    const shipyards = [{ cell: hex(0, -3), edge: north[16]! }];
    const banned = riverWater(rivers, north[16]!, terrain);
    let raised = 0;
    for (let day = 1; day <= 120; day++) {
      const plan = planMapEvent(data, {
        terrain,
        radius: 12,
        villages: [hex(0, 1)],
        taken: new Set([hexKey(hex(0, 1))]),
        sites: [],
        rivers,
        shipyards,
        activeFronts: [FRONTS[0]],
        seed: 7,
        day,
        players: 1,
      });
      if (plan?.kind !== 'shipyard') continue;
      raised++;
      expect(banned.has(hexKey(plan.cell))).toBe(false);
    }
    // The other river still gets them.
    expect(raised).toBeGreaterThan(0);
  });
});
