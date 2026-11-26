import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { raidLoot } from '../src/sim/raids.js';

const data = loadGameData();

describe('raid loot', () => {
  it('grows with each stage deeper and with the front hatred', () => {
    const base = raidLoot(data, 'east', 10, false);
    const greed = data.enemies.fronts.east!.personality.lootFactor;
    expect(base.wood).toBe(Math.round(data.raids.loot.perKill.wood * 10 * greed));
    // The third field: x(1 + 0.5 x 2).
    expect(raidLoot(data, 'east', 10, false, 3).wood).toBe(Math.round(data.raids.loot.perKill.wood * 10 * greed * (1 + 2 * data.raids.loot.perStage)));
    // +60% hatred: x1.6.
    expect(raidLoot(data, 'east', 10, false, 1, 0.6).wood).toBe(Math.round(data.raids.loot.perKill.wood * 10 * greed * (1 + 0.6 * data.raids.loot.perHatred)));
    // The North gives its small share of it, richer all the same.
    expect(raidLoot(data, 'north', 10, true, 4, 0.1).iron).toBeGreaterThan(raidLoot(data, 'north', 10, true).iron);
  });
});
