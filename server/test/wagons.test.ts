import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { wagonFortBonus } from '../src/sim/field.js';
import { reserveCapacity, storeFromArmy, takeForArmy, topUpReserve } from '../src/sim/reserve.js';
import { amountsAt } from '../src/sim/resources.js';
import { fullSupply } from '../src/sim/supply.js';
import { newVillage } from '../src/sim/village.js';

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

describe('the military reserve', () => {
  const village = newVillage(data, T0, 1);
  const plots = { ...village.plots, c2: { building: 'barracks', level: 2 }, c3: { building: 'stables', level: 1 } };
  const state = { ...village, plots };

  it('keeps 200 grain per level of each military building', () => {
    expect(reserveCapacity(data, plots)).toBe(600);
  });

  it('fills from the granary; an army takes from it alone; grain brought home goes into it first', () => {
    const grain = amountsAt(state.ledger, T0).grain;
    const full = topUpReserve(data, state, T0);
    expect(full.reserve).toBe(Math.min(600, grain));
    expect(amountsAt(full.ledger, T0).grain).toBe(grain - full.reserve!);
    const left = takeForArmy(full, 100);
    expect(left.reserve).toBe(full.reserve! - 100);
    expect(amountsAt(left.ledger, T0).grain).toBe(amountsAt(full.ledger, T0).grain);
    const back = storeFromArmy(data, left, 150, T0);
    expect(back.reserve).toBe(Math.min(600, left.reserve! + 150));
  });
});
