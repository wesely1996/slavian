import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { approachAngle, armySpeed, fighters, joinBonus, shareOf, splitLosses, validateArmy } from '../src/sim/armies.js';
import { hex } from '../src/sim/hex.js';

const data = loadGameData();

describe('armies', () => {
  it('march with fighters only, at the slowest pace', () => {
    expect(fighters(data, { spearman: 5, scout: 3, settler: 1, horseman: 0 })).toEqual({ spearman: 5 });
    expect(armySpeed(data, { spearman: 5, horseman: 2 })).toBe(Math.min(data.units.units.spearman!.speed, data.units.units.horseman!.speed));
    expect(() => validateArmy(data, { scout: 2 }, 'support')).toThrow(/don't march/);
    expect(() => validateArmy(data, { spearman: 0 }, 'support')).toThrow(/at least one/);
    expect(() => validateArmy(data, { spearman: 10, horseman: 2 }, 'harass')).toThrow(/mostly cavalry/);
    expect(validateArmy(data, { spearman: 1, horseman: 4 }, 'harass')).toEqual({ spearman: 1, horseman: 4 });
    expect(shareOf(data, { spearman: 9, archer: 1, scout: 4 }, 0.5)).toEqual({ spearman: 4 });
  });

  it('get a pincer bonus coming from another side, scaled by size', () => {
    const village = hex(0, 0);
    expect(approachAngle(village, hex(1, 0), hex(1, 0))).toBeCloseTo(0);
    expect(approachAngle(village, hex(1, 0), hex(-1, 0))).toBeCloseTo(180);
    expect(approachAngle(village, hex(1, 0), hex(0, 1))).toBeCloseTo(60);
    const { pincer, harass } = data.armies;
    expect(joinBonus(data, { orders: 'reinforce', armySize: 10, hordeSize: 20, angle: 60 })).toBe(0);
    expect(joinBonus(data, { orders: 'reinforce', armySize: 10, hordeSize: 20, angle: 180 })).toBeCloseTo(Math.min(pincer.maxBonus, pincer.scale * 0.5));
    expect(joinBonus(data, { orders: 'support', armySize: 100, hordeSize: 20, angle: 180 })).toBe(pincer.maxBonus);
    expect(joinBonus(data, { orders: 'harass', armySize: 5, hordeSize: 50, angle: 0 })).toBeCloseTo(Math.min(harass.maxBonus, harass.scale * 0.1));
  });

  it('share losses in proportion to what each force brought', () => {
    const forces = [{ spearman: 10, archer: 4 }, { spearman: 30 }, { archer: 4 }];
    const split = splitLosses({ spearman: 8, archer: 3 }, forces);
    expect(split[0]!.spearman! + split[1]!.spearman!).toBe(8);
    expect(split[1]!.spearman).toBe(6);
    expect((split[0]!.archer ?? 0) + (split[2]!.archer ?? 0)).toBe(3);
    expect(splitLosses({ spearman: 99 }, forces).reduce((n, s) => n + (s.spearman ?? 0), 0)).toBe(40);
    expect(splitLosses({ horseman: 3 }, forces)).toEqual([{}, {}, {}]);
  });
});
