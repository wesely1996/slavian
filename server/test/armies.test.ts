import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { approachAngle, armySpeed, fighters, joinBonus, shareOf, splitLosses, terrainRelief, validateArmy } from '../src/sim/armies.js';
import { hex } from '../src/sim/hex.js';

const data = loadGameData();

describe('armies', () => {
  it('march with fighters only, at the slowest pace', () => {
    expect(fighters(data, { spearman: 5, scout: 3, settler: 1, horseman: 0 })).toEqual({ spearman: 5 });
    expect(armySpeed(data, { spearman: 5, horseman: 2 })).toBe(Math.min(data.units.units.spearman!.speed, data.units.units.horseman!.speed));
    expect(() => validateArmy(data, { scout: 2 }, 'support')).toThrow(/at least one soldier/);
    expect(() => validateArmy(data, { spearman: 0 }, 'support')).toThrow(/at least one/);
    expect(() => validateArmy(data, { spearman: 10, horseman: 2 }, 'harass')).toThrow(/mostly cavalry/);
    expect(validateArmy(data, { spearman: 1, horseman: 4 }, 'harass')).toEqual({ spearman: 1, horseman: 4 });
    // Scouts march along (they don't count against the cavalry share), never as soldiers.
    expect(validateArmy(data, { horseman: 4, scout: 3, pathfinder: 1 }, 'harass')).toEqual({ horseman: 4, scout: 3, pathfinder: 1 });
    expect(() => validateArmy(data, { settler: 1, spearman: 1 }, 'hold')).toThrow(/don't march/);
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

describe('pathfinders', () => {
  it('take 5% of harsh terrain\'s slowness each, at most half', () => {
    expect(terrainRelief(data, { spearman: 10 })).toBe(0);
    expect(terrainRelief(data, { spearman: 10, pathfinder: 3 })).toBeCloseTo(0.15);
    expect(terrainRelief(data, { pathfinder: 40 })).toBe(0.5);
  });
});

describe('large military caravans', () => {
  it('carry foot soldiers, the slowest first, who then set no pace', () => {
    const wagon = data.units.units.large_caravan!;
    expect(wagon.transports).toEqual({ infantry: 10, engines: 1 });
    expect(wagon.supplyGrain).toBe(300);
    // Ten spearmen ride: the wagon's pace.
    expect(armySpeed(data, { spearman: 10, large_caravan: 1 })).toBe(wagon.speed);
    // Eleven: one walks.
    expect(armySpeed(data, { spearman: 11, large_caravan: 1 })).toBe(data.units.units.spearman!.speed);
    // The slow shields ride first; the spearmen walking set the pace.
    expect(armySpeed(data, { large_shield: 10, spearman: 5, large_caravan: 1 })).toBe(data.units.units.spearman!.speed);
    // Riders never ride in it.
    expect(armySpeed(data, { horseman: 5, large_caravan: 1 })).toBe(wagon.speed);
    // A siege engine takes a whole wagon, before any foot soldier: with one
    // wagon the onager rides and the spearmen walk; with two, all ride.
    expect(armySpeed(data, { onager: 1, large_caravan: 1 })).toBe(wagon.speed);
    expect(armySpeed(data, { onager: 1, spearman: 5, large_caravan: 1 })).toBe(data.units.units.spearman!.speed);
    expect(armySpeed(data, { onager: 1, spearman: 10, large_caravan: 2 })).toBe(wagon.speed);
    expect(armySpeed(data, { onager: 2, large_caravan: 1 })).toBe(data.units.units.onager!.speed);
  });
});
