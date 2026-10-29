// Standing orders: what each kind would do now. The scheduler applies it.
import type { GameData } from '../data/index.js';
import { RuleError } from '../errors.js';
import { mapResources, RESOURCE_KINDS, type Resources } from './resources.js';
import { outpostPlots, type VillageState } from './village.js';

export type StandingOrder =
  | { kind: 'train'; unit: string; batch: number; target: number }
  | { kind: 'rebuild' }
  | { kind: 'surplus'; share: number }
  // A supply route: keep the fort or supply point `fortId` stocked to
  // `target` grain, sent by caravan from the order's village.
  | { kind: 'supply'; fortId: number; target: number };

// Standing orders a village may keep: one more every few Hall levels.
export function ordersLimit(data: GameData, hallLevel: number): number {
  return data.orders.maxPerVillage + Math.floor(hallLevel / data.orders.hallLevelsPerOrder);
}

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
  if (order.kind === 'supply') {
    const most = Math.max(data.field.fort.grainCapacity, data.field.supplyPoint.grainCapacity);
    if (!Number.isInteger(order.target) || order.target < data.orders.supplyMinLoad || order.target > most) {
      throw new RuleError(`Keep between ${data.orders.supplyMinLoad} and ${most} grain there`);
    }
  }
  return order;
}

// The grain to send on a supply route now: what the store lacks of
// `target` (counting what is on the way), trimmed to what the village has
// and its caravans at home can carry; 0 when that is too little to bother.
export function supplyLoad(data: GameData, input: { target: number; stored: number; onTheWay: number; capacity: number; grain: number; canCarry: number }): number {
  const missing = Math.floor(Math.min(input.target, input.capacity) - input.stored - input.onTheWay);
  const load = Math.min(missing, Math.floor(input.grain), Math.floor(input.canCarry));
  return load < data.orders.supplyMinLoad ? 0 : load;
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
