import { describe, expect, it } from 'vitest';
import {
  amountsAt,
  InsufficientResourcesError,
  settle,
  spend,
  TimeTravelError,
  withRates,
  type ResourceLedger,
} from '../src/sim/resources.js';

const T0 = new Date('2026-01-01T00:00:00Z');
const hours = (n: number) => new Date(T0.getTime() + n * 3_600_000);

const ledger: ResourceLedger = {
  amounts: { wood: 100, stone: 100, grain: 100, iron: 100 },
  ratesPerHour: { wood: 10, stone: 0, grain: -20, iron: 50 },
  capacity: { wood: 1000, stone: 1000, grain: 1000, iron: 200 },
  settledAt: T0,
};

describe('resource ledger', () => {
  it('accrues linearly with time', () => {
    expect(amountsAt(ledger, hours(2.5)).wood).toBeCloseTo(125);
    expect(amountsAt(ledger, hours(2.5)).stone).toBe(100);
  });

  it('caps production at capacity', () => {
    expect(amountsAt(ledger, hours(10)).iron).toBe(200);
  });

  it('never drops below zero', () => {
    expect(amountsAt(ledger, hours(10)).grain).toBe(0);
  });

  it('keeps a surplus above capacity instead of clamping it away', () => {
    const over = { ...ledger, amounts: { ...ledger.amounts, iron: 500 } };
    expect(amountsAt(over, hours(1)).iron).toBe(500);
  });

  it('rejects reads before the settle time', () => {
    expect(() => amountsAt(ledger, hours(-1))).toThrow(TimeTravelError);
  });

  it('settling does not change future amounts', () => {
    const settled = settle(ledger, hours(1));
    expect(amountsAt(settled, hours(3))).toEqual(amountsAt(ledger, hours(3)));
  });

  it('applies new rates only from the change onwards', () => {
    const changed = withRates(ledger, hours(1), { ...ledger.ratesPerHour, wood: 100 });
    expect(amountsAt(changed, hours(2)).wood).toBeCloseTo(100 + 10 + 100);
  });

  it('spends from the settled amount', () => {
    const after = spend(ledger, hours(1), { wood: 110, stone: 0, grain: 0, iron: 0 });
    expect(after.amounts.wood).toBeCloseTo(0);
    expect(after.settledAt).toEqual(hours(1));
  });

  it('refuses to overspend and reports what is missing', () => {
    try {
      spend(ledger, T0, { wood: 150, stone: 0, grain: 0, iron: 0 });
      expect.unreachable();
    } catch (error) {
      expect(error).toBeInstanceOf(InsufficientResourcesError);
      expect((error as InsufficientResourcesError).missing.wood).toBe(50);
    }
  });
});
