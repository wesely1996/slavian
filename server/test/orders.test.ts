import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { rebuildTargets, surplusLoad, trainCount, validateOrder } from '../src/sim/orders.js';
import { newVillage, type VillageState } from '../src/sim/village.js';

const data = loadGameData();
const T0 = new Date('2026-06-01T00:00:00Z');
const res = (wood = 0, stone = 0, grain = 0, iron = 0) => ({ wood, stone, grain, iron });

describe('standing orders', () => {
  it('are checked when placed', () => {
    expect(validateOrder(data, { kind: 'train', unit: 'spearman', batch: 5, target: 20 })).toBeTruthy();
    expect(() => validateOrder(data, { kind: 'train', unit: 'dragon', batch: 5, target: 20 })).toThrow(/Unknown unit/);
    expect(() => validateOrder(data, { kind: 'train', unit: 'spearman', batch: 0, target: 20 })).toThrow(/Batches/);
    expect(() => validateOrder(data, { kind: 'train', unit: 'spearman', batch: 10, target: 5 })).toThrow(/at least one batch/);
    expect(() => validateOrder(data, { kind: 'surplus', share: 0.1 })).toThrow(/between 30% and 95%/);
    expect(validateOrder(data, { kind: 'rebuild' })).toEqual({ kind: 'rebuild' });
  });

  it('train towards the target a batch at a time', () => {
    expect(trainCount({ batch: 5, target: 20 }, 0)).toBe(5);
    expect(trainCount({ batch: 5, target: 20 }, 17)).toBe(3);
    expect(trainCount({ batch: 5, target: 20 }, 25)).toBe(0);
  });

  it('rebuild outposts below their best level, unless already queued', () => {
    const base = newVillage(data, T0, 1);
    const v: VillageState = {
      ...base,
      plots: {
        ...base.plots,
        'o3,0': { building: 'outpost', level: 0, terrain: 'forest', peak: 2 },
        'o1,0': { building: 'outpost', level: 2, terrain: 'plains', peak: 2 },
        'o2,1': { building: 'outpost', level: 1, terrain: 'hills', peak: 3 },
      },
      queue: [{ plot: 'o2,1', building: 'outpost', targetLevel: 2, startsAt: T0, completesAt: T0 }],
    };
    expect(rebuildTargets(v)).toEqual(['o3,0']);
  });

  it('send what lies above the share of storage, as much as caravans carry', () => {
    const cap = res(1000, 1000, 1000, 1000);
    expect(surplusLoad(data, res(900, 500, 820, 0), cap, 0.8, 5000)).toEqual(res(100, 0, 20, 0));
    expect(surplusLoad(data, res(850, 500, 800, 0), cap, 0.8, 5000)).toBeNull();
    expect(surplusLoad(data, res(1000, 1000, 0, 0), cap, 0.5, 500)).toEqual(res(250, 250, 0, 0));
    expect(surplusLoad(data, res(1000, 1000, 0, 0), cap, 0.5, 0)).toBeNull();
  });
});
