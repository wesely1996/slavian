import { describe, expect, it } from 'vitest';
import { loadGameData, type TerrainId } from '../src/data/index.js';
import { hex } from '../src/sim/hex.js';
import {
  caravanRoute,
  caravansAt,
  caravansFor,
  receive,
  store,
  vaultCapacity,
  vaultUpgradeCost,
  vaultUpgradeMs,
  withdraw,
} from '../src/sim/logistics.js';
import type { Resources } from '../src/sim/resources.js';

const data = loadGameData();
const res = (wood = 0, stone = 0, grain = 0, iron = 0): Resources => ({ wood, stone, grain, iron });
const T0 = new Date('2026-03-01T00:00:00Z');

describe('caravans', () => {
  it('a Caravan Yard level adds caravans, each carrying a fixed load', () => {
    expect(caravansAt(data, 0)).toBe(0);
    expect(caravansAt(data, 3)).toBe(3 * data.logistics.caravan.caravansPerYardLevel);
    const capacity = data.logistics.caravan.capacity;
    expect(caravansFor(data, res(capacity))).toBe(1);
    expect(caravansFor(data, res(capacity, 1))).toBe(2);
    expect(() => caravansFor(data, res())).toThrow(/Nothing to carry/);
    expect(() => caravansFor(data, res(-5, 10))).toThrow(/whole, non-negative/);
    expect(() => caravansFor(data, res(1.5))).toThrow(/whole, non-negative/);
  });

  it('travels the road at caravan pace, slowed by terrain', () => {
    const terrain = new Map<string, TerrainId>([
      ['0,0', 'holy_city'],
      ['1,0', 'plains'],
      ['2,0', 'forest'],
      ['1,-1', 'lake'],
    ]);
    const path = caravanRoute(data, terrain, hex(2, 0), hex(0, 0), 2);
    const hourMs = 3_600_000 / data.logistics.caravan.speed / 2;
    expect(path.map((s) => [s.q, s.r])).toEqual([[2, 0], [1, 0], [0, 0]]);
    expect(path.map((s) => s.atMs)).toEqual([0, Math.round(hourMs), Math.round(2 * hourMs)]);
    expect(() => caravanRoute(data, terrain, hex(2, 0), hex(1, -1), 1)).toThrow(/No road/);
  });
});

describe('the vault', () => {
  it('grows by level and is paid for from its own stores', () => {
    const v = data.logistics.vault;
    expect(vaultCapacity(data, 1)).toBe(v.baseCapacity);
    expect(vaultCapacity(data, 3)).toBeCloseTo(v.baseCapacity * v.capacityGrowth ** 2);
    expect(vaultUpgradeCost(data, 2)).toEqual(v.upgradeCost);
    expect(vaultUpgradeCost(data, 3).wood).toBe(Math.round(v.upgradeCost.wood * v.costGrowth));
    expect(vaultUpgradeMs(data, 2, 10)).toBe(v.upgradeSeconds * 100);
  });

  it('stores up to capacity and gives back what it holds', () => {
    expect(store(res(2900, 0), 3000, res(300, 50))).toEqual({ amounts: res(3000, 50), leftover: res(200, 0) });
    expect(store(res(3500), 3000, res(10))).toEqual({ amounts: res(3500), leftover: res(10) });
    expect(withdraw(res(100, 500), res(300, 200))).toEqual({ amounts: res(0, 300), taken: res(100, 200) });
  });

  it('a village takes deliveries up to its storehouse', () => {
    const ledger = { amounts: res(900, 0, 0, 0), ratesPerHour: res(100, 0, 0, 0), capacity: res(1000, 1000, 1000, 1000), settledAt: T0 };
    const later = new Date(T0.getTime() + 30 * 60_000);
    const { ledger: after, leftover } = receive(ledger, later, res(200, 300));
    expect(after.amounts).toEqual(res(1000, 300));
    expect(after.settledAt).toEqual(later);
    expect(leftover).toEqual(res(150, 0));
  });
});
