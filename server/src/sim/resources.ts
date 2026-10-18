// Lazy resource ledger: amounts are stored together with the time they were
// last settled and the current rates. The current amount is computed when
// read; it is written back only when rates change or resources are spent.

export const RESOURCE_KINDS = ['wood', 'stone', 'grain', 'iron'] as const;
export type ResourceKind = (typeof RESOURCE_KINDS)[number];
export type Resources = Record<ResourceKind, number>;

export interface ResourceLedger {
  readonly amounts: Resources;
  readonly ratesPerHour: Resources;
  readonly capacity: Resources;
  readonly settledAt: Date;
}

const MS_PER_HOUR = 3_600_000;

export function emptyResources(): Resources {
  return { wood: 0, stone: 0, grain: 0, iron: 0 };
}

export function mapResources(fn: (kind: ResourceKind) => number): Resources {
  return { wood: fn('wood'), stone: fn('stone'), grain: fn('grain'), iron: fn('iron') };
}

export class TimeTravelError extends Error {
  constructor(settledAt: Date, at: Date) {
    super(`Ledger settled at ${settledAt.toISOString()} cannot be read at earlier ${at.toISOString()}`);
  }
}

export class InsufficientResourcesError extends Error {
  constructor(readonly missing: Resources) {
    super(`Insufficient resources: missing ${JSON.stringify(missing)}`);
  }
}

export function amountsAt(ledger: ResourceLedger, at: Date): Resources {
  const hours = (at.getTime() - ledger.settledAt.getTime()) / MS_PER_HOUR;
  if (hours < 0) throw new TimeTravelError(ledger.settledAt, at);
  return mapResources((kind) => {
    const amount = ledger.amounts[kind];
    const rate = ledger.ratesPerHour[kind];
    const cap = ledger.capacity[kind];
    const projected = amount + rate * hours;
    if (rate > 0) {
      // Production never pushes past capacity, but never removes a surplus
      // that arrived some other way (e.g. a caravan) either.
      return Math.max(amount, Math.min(projected, cap));
    }
    return Math.max(0, projected);
  });
}

export function settle(ledger: ResourceLedger, at: Date): ResourceLedger {
  return { ...ledger, amounts: amountsAt(ledger, at), settledAt: at };
}

export function withRates(
  ledger: ResourceLedger,
  at: Date,
  ratesPerHour: Resources,
  capacity: Resources = ledger.capacity,
): ResourceLedger {
  return { ...settle(ledger, at), ratesPerHour, capacity };
}

export function missingFor(amounts: Resources, cost: Resources): Resources {
  return mapResources((kind) => Math.max(0, cost[kind] - amounts[kind]));
}

export function spend(ledger: ResourceLedger, at: Date, cost: Resources): ResourceLedger {
  const settled = settle(ledger, at);
  const missing = missingFor(settled.amounts, cost);
  if (RESOURCE_KINDS.some((kind) => missing[kind] > 0)) throw new InsufficientResourcesError(missing);
  return {
    ...settled,
    amounts: mapResources((kind) => settled.amounts[kind] - cost[kind]),
  };
}
