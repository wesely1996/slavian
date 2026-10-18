import { describe, expect, it } from 'vitest';
import { loadGameData, type TerrainId } from '../src/data/index.js';
import { adminUpkeepFor, recommendedGarrison, settleProblem } from '../src/sim/expansion.js';
import { hex } from '../src/sim/hex.js';
import { newVillage, unitCost, villageRates } from '../src/sim/village.js';

const data = loadGameData();
const T0 = new Date('2026-04-01T00:00:00Z');

describe('founding villages', () => {
  const site = (q: number, r: number, terrain: TerrainId | undefined = 'plains', outposts: string[] = []) => ({
    cell: hex(q, r),
    terrain,
    home: hex(2, 0),
    villages: [hex(2, 0), hex(-2, 0)],
    outposts: new Set(outposts),
  });

  it('needs a free, settleable hex near enough and far enough', () => {
    expect(settleProblem(data, site(5, 0))).toBeNull();
    expect(settleProblem(data, { ...site(5, 0), terrain: undefined })).toMatch(/not on the map/);
    expect(settleProblem(data, site(5, 0, 'swamp'))).toMatch(/can't be founded on Swamp/);
    expect(settleProblem(data, site(9, 0))).toMatch(/at most 6 hexes/);
    expect(settleProblem(data, site(4, 0))).toMatch(/at least 3 hexes apart/);
    expect(settleProblem(data, site(1, -1))).toMatch(/Holy City|apart/);
    expect(settleProblem(data, site(5, 0, 'plains', ['5,0']))).toMatch(/outpost/);
  });

  it('settlers and administration get dearer with every village', () => {
    const base = data.units.units.settler!.cost;
    expect(unitCost(data, 'settler', 3, 1)).toEqual({ wood: base.wood * 3, stone: base.stone * 3, grain: base.grain * 3, iron: base.iron * 3 });
    expect(unitCost(data, 'settler', 1, 3).wood).toBe(Math.round(base.wood * 1.5 ** 2));
    expect(unitCost(data, 'spearman', 2, 5)).toEqual(unitCost(data, 'spearman', 2, 1));
    expect(adminUpkeepFor(data, 1)).toBe(data.expansion.adminUpkeepPerVillage);
    expect(adminUpkeepFor(data, 3)).toBe(3 * data.expansion.adminUpkeepPerVillage);
    expect(recommendedGarrison(data, 1)).toBe(data.expansion.recommendedGarrison.base);
    expect(recommendedGarrison(data, 3)).toBe(data.expansion.recommendedGarrison.base + 2 * data.expansion.recommendedGarrison.perVillage);
  });

  it('a founded village starts with its own stores and pays its upkeep in grain', () => {
    const first = newVillage(data, T0, 2);
    const founded = newVillage(data, T0, 2, { startingResources: data.expansion.startingResources, adminUpkeep: 12 });
    expect(founded.ledger.amounts).toEqual(data.expansion.startingResources);
    expect(founded.adminUpkeep).toBe(12);
    expect(founded.ledger.ratesPerHour.grain).toBeCloseTo(first.ledger.ratesPerHour.grain - 24);
    expect(villageRates(data, founded, 2)).toEqual(founded.ledger.ratesPerHour);
  });
});
