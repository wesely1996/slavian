import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { wagonFortBonus } from '../src/sim/field.js';
import { quarterOwed, settlementFloor, spareGrain, storeFloor } from '../src/sim/quarters.js';
import { supplyLeft, outOfFoodAt } from '../src/sim/supply.js';
import { fullSupply } from '../src/sim/supply.js';
import { capacity, newVillage } from '../src/sim/village.js';

const data = loadGameData();
const T0 = new Date('2026-03-01T00:00:00Z');
const ready = new Date(T0.getTime() - 1000);

describe('military caravans', () => {
  it('carry 200 grain for the army on top of their own food', () => {
    const wagon = data.units.units.supply_wagon!;
    expect(fullSupply(data, { supply_wagon: 2 })).toBe(2 * (wagon.upkeepPerHour * wagon.supplyHours + 200));
  });

  it('give 10% per wagon for each 10 soldiers, rounded up, at most 30%', () => {
    const bonus = (units: Record<string, number>, at: Date | null = ready) => wagonFortBonus(data, [{ units, wagonFortAt: at }], T0);
    expect(bonus({ spearman: 10, supply_wagon: 1 })).toBeCloseTo(0.1);
    expect(bonus({ spearman: 30, supply_wagon: 3 })).toBeCloseTo(0.1);
    expect(bonus({ spearman: 11, supply_wagon: 1 })).toBeCloseTo(0.05);
    expect(bonus({ spearman: 10, supply_wagon: 2 })).toBeCloseTo(0.2);
    expect(bonus({ spearman: 10, supply_wagon: 5 })).toBeCloseTo(0.3);
    // Not yet in a ring, or no wagons: nothing.
    expect(bonus({ spearman: 10, supply_wagon: 1 }, new Date(T0.getTime() + 1000))).toBe(0);
    expect(bonus({ spearman: 10, supply_wagon: 1 }, null)).toBe(0);
    expect(bonus({ spearman: 10 })).toBe(0);
  });
});

describe('quarters and the grain silo', () => {
  it('a grain silo adds grain storage alone, as a storehouse does for everything', () => {
    const village = newVillage(data, T0, 1);
    const base = capacity(data, village.plots);
    const silo = capacity(data, { ...village.plots, c2: { building: 'grain_silo', level: 2 } });
    expect(silo.wood).toBe(base.wood);
    expect(silo.grain).toBeCloseTo(base.grain + data.buildings.village.baseCapacity * (1.3 ** 2 - 1));
  });

  it('settlements and forts feed armies to the last grain unless a floor is set', () => {
    expect(settlementFloor(data, null, 1000)).toBe(0);
    expect(settlementFloor(data, 200, 1000)).toBe(200);
    expect(storeFloor(null)).toBe(0);
    expect(storeFloor(300)).toBe(300);
    expect(spareGrain(800, 500)).toBe(300);
    expect(spareGrain(400, 500)).toBe(0);
  });

  it('a quartered army eats half its upkeep from the place, and none of its own grain', () => {
    const units = { spearman: 10 };
    const upkeep = data.units.units.spearman!.upkeepPerHour * 10;
    const later = new Date(T0.getTime() + 2 * 3_600_000);
    expect(quarterOwed(data, units, T0, later, 1)).toBeCloseTo(upkeep);
    const army = { units, supply: 100, supplyAt: T0, hungrySince: null, quarteredAt: T0 };
    expect(supplyLeft(data, army, later, 1)).toBe(100);
    expect(outOfFoodAt(data, army, 1)).toBeNull();
    expect(supplyLeft(data, { ...army, quarteredAt: null }, later, 1)).toBeCloseTo(100 - 2 * upkeep);
  });
});
