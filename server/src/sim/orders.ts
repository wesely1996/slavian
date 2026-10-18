// Standing orders: what each kind would do now. The scheduler applies it.
import type { GameData } from '../data/index.js';
import { RuleError } from '../errors.js';
import { mapResources, RESOURCE_KINDS, type Resources } from './resources.js';
import { outpostPlots, type VillageState } from './village.js';

export type StandingOrder =
  | { kind: 'train'; unit: string; batch: number; target: number }
  | { kind: 'rebuild' }
  | { kind: 'surplus'; share: number };

export function validateOrder(data: GameData, order: StandingOrder): StandingOrder {
  if (order.kind === 'train') {
    if (!data.units.units[order.unit]) throw new RuleError(`Unknown unit "${order.unit}"`);
    if (!Number.isInteger(order.batch) || order.batch < 1 || order.batch > data.units.maxBatch) {
      throw new RuleError(`Batches are 1 to ${data.units.maxBatch}`);
    }
    if (!Number.isInteger(order.target) || order.target < order.batch) throw new RuleError('Keep at least one batch');
  }
  if (order.kind === 'surplus') {
    const { min, max } = data.orders.surplusShare;
    if (!(order.share >= min && order.share <= max)) {
      throw new RuleError(`Keep between ${Math.round(min * 100)}% and ${Math.round(max * 100)}% of storage`);
    }
  }
  return order;
}

// How many to train now to work towards `target`, counting units at home,
// away and in training.
export function trainCount(order: { batch: number; target: number }, have: number): number {
  return Math.max(0, Math.min(order.batch, order.target - have));
}

// Outposts below the best level they ever had, with nothing queued for them.
export function rebuildTargets(state: VillageState): string[] {
  return outpostPlots(state.plots).filter((plot) => {
    const p = state.plots[plot]!;
    return p.level < (p.peak ?? p.level) && !state.queue.some((item) => item.plot === plot);
  });
}

// What lies above `share` of storage, trimmed to what the caravans at home
// can carry; null when it's too little to bother.
export function surplusLoad(
  data: GameData,
  amounts: Resources,
  capacity: Resources,
  share: number,
  canCarry: number,
): Resources | null {
  const above = mapResources((kind) => Math.max(0, Math.floor(amounts[kind] - capacity[kind] * share)));
  const total = RESOURCE_KINDS.reduce((sum, kind) => sum + above[kind], 0);
  if (total < Math.max(1, data.orders.minSurplus) || canCarry <= 0) return null;
  if (total <= canCarry) return above;
  const scale = canCarry / total;
  return mapResources((kind) => Math.floor(above[kind] * scale));
}
