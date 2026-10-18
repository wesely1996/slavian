import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { RuleError } from '../src/errors.js';
import { amountsAt } from '../src/sim/resources.js';
import {
  buildQueueLimit,
  buildSeconds,
  capacity,
  completeBuild,
  HALL_PLOT,
  levelCost,
  newVillage,
  plotsFromLegacyLevels,
  productionPerHour,
  queueBuild,
  unlockedSlots,
  type VillageState,
} from '../src/sim/village.js';

const data = loadGameData();
const T0 = new Date('2026-01-01T00:00:00Z');
const woodcutter = data.buildings.buildings.woodcutter!;
const { village } = data.buildings;

function rich(state: VillageState): VillageState {
  return {
    ...state,
    ledger: { ...state.ledger, amounts: { wood: 9e6, stone: 9e6, grain: 9e6, iron: 9e6 }, capacity: { wood: 9e9, stone: 9e9, grain: 9e9, iron: 9e9 } },
  };
}

// Queues and immediately completes one build order.
function build(state: VillageState, order: Parameters<typeof queueBuild>[2]): VillageState {
  const { state: queued, queued: item } = queueBuild(data, state, order, state.ledger.settledAt, 1);
  return completeBuild(data, queued, item.plot, item.targetLevel, item.completesAt, 1);
}

describe('game data', () => {
  it('loads and validates', () => {
    expect(Object.keys(data.buildings.buildings)).toContain('elder_hall');
    expect(village.fields.length).toBeGreaterThan(0);
  });
});

describe('village layout', () => {
  it('starts with fields at level 0 and the Elder\'s Hall in the first slot', () => {
    const v = newVillage(data, T0, 1);
    expect(Object.keys(v.plots).filter((id) => id.startsWith('f'))).toHaveLength(village.fields.length);
    expect(Object.keys(v.plots).filter((id) => id.startsWith('c'))).toHaveLength(village.centerSlots);
    expect(v.plots.f0).toEqual({ building: village.fields[0], level: 0 });
    expect(v.plots[HALL_PLOT]).toEqual({ building: 'elder_hall', level: 1 });
    expect(v.plots.c1).toEqual({ building: null, level: 0 });
    expect(v.levels).toEqual({ elder_hall: 1 });
  });

  it('a bigger Elder\'s Hall unlocks slots and queue places', () => {
    expect(unlockedSlots(data, 1)).toBe(village.slotsUnlockedAtStart);
    expect(unlockedSlots(data, 5)).toBe(village.slotsUnlockedAtStart + 4 * village.slotsPerHallLevel);
    expect(unlockedSlots(data, 99)).toBe(village.centerSlots);
    expect(buildQueueLimit(data, 1)).toBe(village.baseQueueLimit);
    expect(buildQueueLimit(data, 3)).toBe(village.baseQueueLimit + 1);
    expect(buildQueueLimit(data, 9)).toBe(village.baseQueueLimit + 3);
  });
});

describe('building', () => {
  it('upgrades each field on its own; production adds up across fields', () => {
    let v = rich(newVillage(data, T0, 1));
    const base = productionPerHour(data, v.plots, 1).wood;
    v = build(v, { plot: 'f0' });
    v = build(v, { plot: 'f1' });
    v = build(v, { plot: 'f1' });
    expect(v.plots.f0!.level).toBe(1);
    expect(v.plots.f1!.level).toBe(2);
    expect(v.levels.woodcutter).toBe(2);
    const prod = woodcutter.production!;
    expect(productionPerHour(data, v.plots, 1).wood).toBeCloseTo(base + prod.basePerHour + prod.basePerHour * prod.growth);
  });

  it('constructs a building in a free unlocked slot, then upgrades it there', () => {
    let v = rich(newVillage(data, T0, 1));
    v = build(v, { plot: 'c2', building: 'barracks' });
    expect(v.plots.c2).toEqual({ building: 'barracks', level: 1 });
    v = build(v, { plot: 'c2' });
    expect(v.levels.barracks).toBe(2);
  });

  it('refuses locked slots, duplicates, wrong kinds and changing a plot', () => {
    const v = rich(newVillage(data, T0, 1));
    const at = v.ledger.settledAt;
    const locked = `c${village.slotsUnlockedAtStart}`;
    expect(() => queueBuild(data, v, { plot: locked, building: 'barracks' }, at, 1)).toThrow(/locked/);
    expect(() => queueBuild(data, v, { plot: 'c1', building: 'woodcutter' }, at, 1)).toThrow(/fields/);
    expect(() => queueBuild(data, v, { plot: 'c1' }, at, 1)).toThrow(/which building/);
    expect(() => queueBuild(data, v, { plot: 'f0', building: 'farm' }, at, 1)).toThrow(/holds a Woodcutter/);
    expect(() => queueBuild(data, v, { plot: 'x9' }, at, 1)).toThrow(RuleError);
    const withBarracks = queueBuild(data, v, { plot: 'c1', building: 'barracks' }, at, 1).state;
    // Already being built in c1: no second one in c2.
    expect(() => queueBuild(data, withBarracks, { plot: 'c2', building: 'barracks' }, at, 1)).toThrow(/already has/);
  });

  it('unlocks more slots as the hall grows', () => {
    let v = rich(newVillage(data, T0, 1));
    const locked = `c${village.slotsUnlockedAtStart}`;
    v = build(v, { plot: HALL_PLOT });
    expect(() => build(v, { plot: locked, building: 'barracks' })).not.toThrow();
  });

  it('picks a plot for orders that only name a building (older clients)', () => {
    let v = rich(newVillage(data, T0, 1));
    v = build(v, 'woodcutter');
    v = build(v, 'woodcutter');
    // The lowest woodcutter field gets the next upgrade.
    expect([v.plots.f0!.level, v.plots.f1!.level]).toEqual([1, 1]);
    v = build(v, 'storehouse');
    expect(v.plots.c1).toEqual({ building: 'storehouse', level: 1 });
    v = build(v, 'storehouse');
    expect(v.plots.c1!.level).toBe(2);
    expect(capacity(data, v.levels).wood).toBeGreaterThan(village.baseCapacity);
  });

  it('scales cost and time with level, world speed and the hall', () => {
    expect(levelCost(woodcutter, 1)).toEqual(woodcutter.cost);
    expect(levelCost(woodcutter, 2).wood).toBe(Math.round(woodcutter.cost.wood * woodcutter.costGrowth));
    expect(buildSeconds(woodcutter, 1, 10)).toBe(woodcutter.buildSeconds / 10);
    let v = rich(newVillage(data, T0, 1));
    const slow = queueBuild(data, v, { plot: 'f0' }, v.ledger.settledAt, 1).queued;
    v = build(v, { plot: HALL_PLOT });
    const fast = queueBuild(data, v, { plot: 'f0' }, v.ledger.settledAt, 1).queued;
    const span = (q: typeof slow) => q.completesAt.getTime() - q.startsAt.getTime();
    expect(span(fast)).toBeLessThan(span(slow));
  });

  it('queues builds back to back, pays up front and enforces the queue limit', () => {
    const v = newVillage(data, T0, 1);
    const first = queueBuild(data, v, { plot: 'f0' }, T0, 1);
    const second = queueBuild(data, first.state, { plot: 'f6' }, T0, 1);
    expect(second.queued.startsAt).toEqual(first.queued.completesAt);
    expect(second.state.ledger.amounts.wood).toBe(
      village.startingResources.wood - levelCost(woodcutter, 1).wood - data.buildings.buildings.farm!.cost.wood,
    );
    expect(() => queueBuild(data, second.state, { plot: 'f3' }, T0, 1)).toThrow(/queue is full/);
  });

  it('completing raises the plot and production from that moment only', () => {
    const { state, queued } = queueBuild(data, newVillage(data, T0, 1), { plot: 'f0' }, T0, 1);
    const done = completeBuild(data, state, 'f0', 1, queued.completesAt, 1);
    expect(done.ledger.ratesPerHour.wood).toBeGreaterThan(state.ledger.ratesPerHour.wood);
    expect(amountsAt(done.ledger, queued.completesAt)).toEqual(amountsAt(state.ledger, queued.completesAt));
    expect(() => completeBuild(data, state, 'f1', 1, T0, 1)).toThrow(RuleError);
  });
});

describe('legacy villages', () => {
  it('lays out per-building levels on plots', () => {
    const plots = plotsFromLegacyLevels(data, { woodcutter: 3, farm: 1, storehouse: 2, barracks: 1 });
    expect(plots.f0).toEqual({ building: 'woodcutter', level: 3 });
    expect(plots.f6).toEqual({ building: 'farm', level: 1 });
    expect(plots[HALL_PLOT]).toEqual({ building: 'elder_hall', level: 1 });
    expect(plots.c1).toEqual({ building: 'storehouse', level: 2 });
    expect(plots.c2).toEqual({ building: 'barracks', level: 1 });
  });
});
