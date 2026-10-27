import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { RuleError } from '../src/errors.js';
import { amountsAt } from '../src/sim/resources.js';
import {
  allUnits,
  batchCompletesAt,
  finishedBy,
  perUnitMs,
  settleTraining,
  upkeepPerHour,
  type TrainingBatch,
} from '../src/sim/training.js';
import { completeBuild, completeTraining, newVillage, queueBuild, queueTraining } from '../src/sim/village.js';

const data = loadGameData();
const T0 = new Date('2026-02-01T12:00:00Z');
const ms = (n: number) => new Date(T0.getTime() + n);

// A village with a level-1 barracks (or another training building) and
// plenty of resources.
function withBarracks(level = 1, building = 'barracks') {
  const fresh = newVillage(data, T0, 1);
  const rich = {
    ...fresh,
    ledger: { ...fresh.ledger, amounts: { wood: 9000, stone: 9000, grain: 9000, iron: 9000 }, capacity: { wood: 9e9, stone: 9e9, grain: 9e9, iron: 9e9 } },
  };
  let state = rich;
  for (let target = 1; target <= level; target++) {
    const { state: queued, queued: item } = queueBuild(data, state, building, state.ledger.settledAt, 1);
    state = completeBuild(data, queued, item.plot, target, item.completesAt, 1);
  }
  return state;
}

describe('training batches', () => {
  const batch: TrainingBatch = { unit: 'spearman', count: 5, startsAt: T0, perUnitMs: 1000 };

  it('finishes one unit per interval', () => {
    expect(finishedBy(batch, ms(-500))).toBe(0);
    expect(finishedBy(batch, ms(999))).toBe(0);
    expect(finishedBy(batch, ms(1000))).toBe(1);
    expect(finishedBy(batch, ms(3500))).toBe(3);
    expect(finishedBy(batch, ms(99_000))).toBe(5);
    expect(batchCompletesAt(batch)).toEqual(ms(5000));
  });

  it('settles finished units into the garrison and keeps the rest training', () => {
    const second: TrainingBatch = { unit: 'archer', count: 2, startsAt: ms(5000), perUnitMs: 2000 };
    const settled = settleTraining({ spearman: 1 }, [batch, second], ms(7000));
    expect(settled.garrison).toEqual({ spearman: 6, archer: 1 });
    expect(settled.training).toEqual([{ unit: 'archer', count: 1, startsAt: ms(7000), perUnitMs: 2000 }]);
    // Settling again at the same time changes nothing.
    expect(settleTraining(settled.garrison, settled.training, ms(7000))).toEqual(settled);
  });

  it('counts units in training for upkeep', () => {
    expect(allUnits({ spearman: 2 }, [batch])).toEqual({ spearman: 7 });
    expect(upkeepPerHour(data, { spearman: 2, horseman: 1 }, 3)).toBe((2 * 1 + 1 * 2) * 3);
  });

  it('trains faster with a bigger barracks and a faster world', () => {
    expect(perUnitMs(data, 'spearman', 1, 1)).toBe(60_000);
    expect(perUnitMs(data, 'spearman', 3, 1)).toBe(Math.round(60_000 * 0.9 ** 2));
    expect(perUnitMs(data, 'spearman', 1, 10)).toBe(6_000);
  });
});

describe('queueTraining', () => {
  it('needs the training building at the required level', () => {
    expect(() => queueTraining(data, newVillage(data, T0, 1), 'spearman', 1, T0, 1)).toThrow(/Barracks level 1/);
    expect(() => queueTraining(data, withBarracks(1), 'axeman', 1, T0, 1)).toThrow(/Barracks level 2/);
    expect(() => queueTraining(data, withBarracks(1), 'scout', 1, T0, 1)).toThrow(/Scout Lodge/);
    expect(() => queueTraining(data, withBarracks(2), 'axeman', 1, withBarracks(2).ledger.settledAt, 1)).not.toThrow();
    // Riders come from the Stables, shooters from the Shooting Range.
    expect(() => queueTraining(data, withBarracks(2), 'horseman', 1, T0, 1)).toThrow(/Stables level 1/);
    expect(() => queueTraining(data, withBarracks(2), 'archer', 1, T0, 1)).toThrow(/Shooting Range level 1/);
    const stables = withBarracks(1, 'stables');
    expect(() => queueTraining(data, stables, 'horseman', 1, stables.ledger.settledAt, 1)).not.toThrow();
    const range = withBarracks(1, 'shooting_range');
    expect(() => queueTraining(data, range, 'archer', 1, range.ledger.settledAt, 1)).not.toThrow();
  });

  it('rejects bad counts and unknown units', () => {
    const state = withBarracks();
    const at = state.ledger.settledAt;
    for (const count of [0, -1, 1.5, data.units.maxBatch + 1]) {
      expect(() => queueTraining(data, state, 'spearman', count, at, 1)).toThrow(RuleError);
    }
    expect(() => queueTraining(data, state, 'dragon', 1, at, 1)).toThrow(RuleError);
  });

  it('pays for the whole batch, queues batches back to back and enforces the limit', () => {
    let state = withBarracks();
    const at = state.ledger.settledAt;
    const before = amountsAt(state.ledger, at);
    const first = queueTraining(data, state, 'spearman', 3, at, 1);
    expect(amountsAt(first.state.ledger, at).wood).toBe(before.wood - 3 * data.units.units.spearman!.cost.wood);
    const second = queueTraining(data, first.state, 'axe_levy', 2, at, 1);
    expect(second.batch.startsAt).toEqual(batchCompletesAt(first.batch));
    state = second.state;
    while (state.training.length < data.units.trainingQueueLimit) {
      state = queueTraining(data, state, 'spearman', 1, at, 1).state;
    }
    expect(() => queueTraining(data, state, 'spearman', 1, at, 1)).toThrow(/queue is full/);
  });

  it('starts paying upkeep when units are drafted', () => {
    const state = withBarracks();
    const at = state.ledger.settledAt;
    const { state: after } = queueTraining(data, state, 'spearman', 10, at, 1);
    // On garrison rations: half their upkeep.
    expect(after.ledger.ratesPerHour.grain).toBe(state.ledger.ratesPerHour.grain - 10 * data.armies.supply.garrisonUpkeep);
    // Finishing training moves units home without changing upkeep.
    const done = completeTraining(after, batchCompletesAt(after.training[0]!));
    expect(done.garrison).toEqual({ spearman: 10 });
    expect(done.training).toEqual([]);
    expect(done.ledger.ratesPerHour.grain).toBe(after.ledger.ratesPerHour.grain);
  });

  it('keeps upkeep when a building completes', () => {
    const state = withBarracks();
    const at = state.ledger.settledAt;
    const trained = queueTraining(data, state, 'spearman', 4, at, 1).state;
    const { state: building, queued } = queueBuild(data, trained, 'farm', at, 1);
    const built = completeBuild(data, building, queued.plot, 1, queued.completesAt, 1);
    const farm = data.buildings.buildings.farm!.production!.basePerHour;
    expect(built.ledger.ratesPerHour.grain).toBeCloseTo(trained.ledger.ratesPerHour.grain + farm);
  });
});
