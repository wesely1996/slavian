// Unit training. A batch trains its units one after another; units that
// finished are counted lazily (like resources), so nothing needs to happen
// per unit. A scheduled event settles each batch when it is done.
import type { GameData } from '../data/index.js';

export type Units = Readonly<Record<string, number>>;

export interface TrainingBatch {
  readonly unit: string;
  readonly count: number;
  readonly startsAt: Date;
  readonly perUnitMs: number;
}

export function batchCompletesAt(batch: TrainingBatch): Date {
  return new Date(batch.startsAt.getTime() + batch.count * batch.perUnitMs);
}

export function finishedBy(batch: TrainingBatch, at: Date): number {
  const elapsed = at.getTime() - batch.startsAt.getTime();
  return Math.max(0, Math.min(batch.count, Math.floor(elapsed / batch.perUnitMs)));
}

// Real-time milliseconds per unit; the training building's level and the
// world speed both shorten it.
export function perUnitMs(data: GameData, unit: string, buildingLevel: number, worldSpeed: number, factor = 1): number {
  const def = data.units.units[unit]!;
  const speedup = data.units.trainingSpeedup ** Math.max(0, buildingLevel - 1) * factor;
  return Math.max(1, Math.round((def.trainSeconds * 1000 * speedup) / worldSpeed));
}

export function addUnits(a: Units, b: Units): Record<string, number> {
  const sum: Record<string, number> = { ...a };
  for (const [unit, count] of Object.entries(b)) sum[unit] = (sum[unit] ?? 0) + count;
  return sum;
}

// Moves units finished by `at` from the batches into the garrison.
export function settleTraining(
  garrison: Units,
  training: readonly TrainingBatch[],
  at: Date,
): { garrison: Units; training: TrainingBatch[] } {
  const finished: Record<string, number> = {};
  const remaining: TrainingBatch[] = [];
  for (const batch of training) {
    const done = finishedBy(batch, at);
    if (done > 0) finished[batch.unit] = (finished[batch.unit] ?? 0) + done;
    if (done < batch.count) {
      remaining.push({
        ...batch,
        count: batch.count - done,
        startsAt: new Date(batch.startsAt.getTime() + done * batch.perUnitMs),
      });
    }
  }
  return { garrison: addUnits(garrison, finished), training: remaining };
}

// Everyone eats: units at home and units still in training.
export function allUnits(garrison: Units, training: readonly TrainingBatch[]): Record<string, number> {
  return training.reduce<Record<string, number>>((sum, b) => addUnits(sum, { [b.unit]: b.count }), { ...garrison });
}

export function upkeepPerHour(data: GameData, units: Units, worldSpeed: number): number {
  let total = 0;
  for (const [unit, count] of Object.entries(units)) total += (data.units.units[unit]?.upkeepPerHour ?? 0) * count;
  return total * worldSpeed;
}
