import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { addSupply, fullSupply, hungerStrikes, hungry, nextHungerCheck, settleSupply, supplyLeft, supplySpeedFactor } from '../src/sim/supply.js';

const data = loadGameData();
const T0 = new Date('2026-03-01T00:00:00Z');
const HOUR = 3_600_000;
const at = (hours: number) => new Date(T0.getTime() + hours * HOUR);

describe('army supply', () => {
  // 10 spearmen eat 10 grain a game hour; world speed 1.
  const army = { units: { spearman: 10 }, supply: fullSupply(data, { spearman: 10 }), supplyAt: T0, hungrySince: null };

  it('carries a day of food and eats it', () => {
    expect(army.supply).toBe(10 * data.units.units.spearman!.supplyHours);
    expect(supplyLeft(data, army, at(6), 1)).toBeCloseTo(army.supply - 60);
    expect(hungry(data, army, at(23), 1)).toBe(false);
    expect(hungry(data, army, at(24), 1)).toBe(true);
    expect(supplySpeedFactor(data, army, at(25), 1)).toBe(data.armies.attrition.slowFactor);
  });

  it('carries what each unit carries: riders more than foot, light foot more than heavy', () => {
    const hours = (unit: string) => fullSupply(data, { [unit]: 1 }) / data.units.units[unit]!.upkeepPerHour;
    expect(hours('horseman')).toBeGreaterThan(hours('spearman'));
    expect(hours('skirmisher')).toBeGreaterThan(hours('spearman'));
    expect(hours('spearman')).toBeGreaterThan(hours('large_shield'));
    expect(fullSupply(data, { spearman: 2, horseman: 1 })).toBe(2 * fullSupply(data, { spearman: 1 }) + fullSupply(data, { horseman: 1 }));
  });

  it('starts to lose men hours after the food runs out, then every hour, and is lost after a day', () => {
    const { lossAfterHours, lostAfterHours, lossShare } = data.armies.attrition;
    expect(nextHungerCheck(data, army, T0, 1)).toEqual(at(24 + lossAfterHours));
    expect(hungerStrikes(data, army, at(24 + lossAfterHours - 1), 1)).toEqual({ lost: false, losses: {} });
    expect(hungerStrikes(data, army, at(24 + lossAfterHours), 1)).toEqual({ lost: false, losses: { spearman: Math.ceil(10 * lossShare) } });
    expect(nextHungerCheck(data, army, at(24 + lossAfterHours), 1)).toEqual(at(24 + lossAfterHours + 1));
    expect(hungerStrikes(data, army, at(24 + lostAfterHours), 1).lost).toBe(true);
  });

  it('keeps when the food ran out when its numbers change, and is fed again by new grain', () => {
    const settled = settleSupply(data, army, at(30), 1);
    expect(settled.hungrySince).toEqual(at(24));
    const thinned = { ...settled, units: { spearman: 5 } };
    expect(nextHungerCheck(data, thinned, at(30), 1)).toEqual(at(24 + data.armies.attrition.lossAfterHours));
    const fed = addSupply(data, thinned, 50, at(30), 1);
    expect(fed.hungrySince).toBeNull();
    expect(hungry(data, fed, at(39), 1)).toBe(false);
    expect(hungry(data, fed, at(40), 1)).toBe(true);
  });
});
