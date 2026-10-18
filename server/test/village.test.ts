import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { amountsAt } from '../src/sim/resources.js';
import {
  buildSeconds,
  capacity,
  completeBuild,
  levelCost,
  newVillage,
  productionPerHour,
  queueBuild,
  RuleError,
} from '../src/sim/village.js';

const data = loadGameData();
const T0 = new Date('2026-01-01T00:00:00Z');
const woodcutter = data.buildings.buildings.woodcutter!;

describe('game data', () => {
  it('loads and validates', () => {
    expect(Object.keys(data.buildings.buildings)).toContain('storehouse');
  });
});

describe('village rules', () => {
  it('scales cost and time with level', () => {
    expect(levelCost(woodcutter, 1)).toEqual(woodcutter.cost);
    expect(levelCost(woodcutter, 2).wood).toBe(Math.round(woodcutter.cost.wood * woodcutter.costGrowth));
    expect(buildSeconds(woodcutter, 1, 1)).toBe(woodcutter.buildSeconds);
    expect(buildSeconds(woodcutter, 1, 10)).toBe(woodcutter.buildSeconds / 10);
  });

  it('world speed multiplies production', () => {
    expect(productionPerHour(data, {}, 3).wood).toBe(data.buildings.village.baseProductionPerHour.wood * 3);
  });

  it('storehouse raises capacity', () => {
    expect(capacity(data, { storehouse: 2 }).wood).toBeGreaterThan(capacity(data, {}).wood);
  });

  it('queues builds back to back and pays up front', () => {
    const village = newVillage(data, T0, 1);
    const first = queueBuild(data, village, 'woodcutter', T0, 1);
    const second = queueBuild(data, first.state, 'woodcutter', T0, 1);
    expect(first.queued.targetLevel).toBe(1);
    expect(second.queued.targetLevel).toBe(2);
    expect(second.queued.startsAt).toEqual(first.queued.completesAt);
    const spent = levelCost(woodcutter, 1).wood + levelCost(woodcutter, 2).wood;
    expect(second.state.ledger.amounts.wood).toBe(data.buildings.village.startingResources.wood - spent);
  });

  it('enforces the queue limit', () => {
    let state = newVillage(data, T0, 1);
    for (let i = 0; i < data.buildings.village.queueLimit; i++) {
      state = queueBuild(data, state, 'farm', T0, 1).state;
    }
    expect(() => queueBuild(data, state, 'farm', T0, 1)).toThrow(RuleError);
  });

  it('rejects unknown buildings', () => {
    expect(() => queueBuild(data, newVillage(data, T0, 1), 'castle', T0, 1)).toThrow(RuleError);
  });

  it('completing a build raises the level and production from that moment', () => {
    const { state, queued } = queueBuild(data, newVillage(data, T0, 1), 'woodcutter', T0, 1);
    const done = completeBuild(data, state, 'woodcutter', 1, queued.completesAt, 1);
    expect(done.levels.woodcutter).toBe(1);
    expect(done.queue).toHaveLength(0);
    expect(done.ledger.ratesPerHour.wood).toBeGreaterThan(state.ledger.ratesPerHour.wood);
    // Old rate applies up to completion.
    expect(amountsAt(done.ledger, queued.completesAt)).toEqual(amountsAt(state.ledger, queued.completesAt));
  });

  it('only completes the head of the queue', () => {
    const { state } = queueBuild(data, newVillage(data, T0, 1), 'woodcutter', T0, 1);
    expect(() => completeBuild(data, state, 'farm', 1, T0, 1)).toThrow(RuleError);
  });
});
