// Caravans and the Holy City vault. A caravan leaves its village with a
// load (or empty, to fetch from the vault), unloads at the other end and
// walks home; whatever didn't fit rides back with it.
import type { GameData, TerrainId } from '../data/index.js';
import { RuleError } from '../errors.js';
import { findPath, hex, hexKey, type Hex } from './hex.js';
import { mapResources, RESOURCE_KINDS, settle, type ResourceLedger, type Resources } from './resources.js';
import type { PathStep } from './waves.js';

const MS_PER_HOUR = 3_600_000;
export const CARAVAN_YARD = 'caravan_yard';
export const HOLY_CITY: Hex = hex(0, 0);

export function caravansAt(data: GameData, yardLevel: number): number {
  return yardLevel * data.logistics.caravan.caravansPerYardLevel;
}

export function total(amounts: Resources): number {
  return RESOURCE_KINDS.reduce((sum, kind) => sum + amounts[kind], 0);
}

// Caravans needed to carry `load`; refuses empty or negative loads.
export function caravansFor(data: GameData, load: Resources): number {
  if (RESOURCE_KINDS.some((kind) => !Number.isInteger(load[kind]) || load[kind] < 0)) {
    throw new RuleError('Loads are whole, non-negative amounts');
  }
  const amount = total(load);
  if (amount <= 0) throw new RuleError('Nothing to carry');
  return Math.ceil(amount / data.logistics.caravan.capacity);
}

// The road between two hexes, timed at caravan pace: each step is the
// hex and the ms after departure the caravan enters it.
export function caravanRoute(
  data: GameData,
  terrain: ReadonlyMap<string, TerrainId>,
  from: Hex,
  to: Hex,
  worldSpeed: number,
): PathStep[] {
  const moveCost = (_: Hex, cell: Hex): number | null => {
    const type = terrain.get(hexKey(cell));
    return type === undefined ? null : data.terrain.terrain[type].moveCost;
  };
  const path = findPath(from, to, moveCost);
  if (!path) throw new RuleError('No road leads there');
  const msPerCost = MS_PER_HOUR / data.logistics.caravan.speed / worldSpeed;
  let atMs = 0;
  return path.map((cell, i) => {
    if (i > 0) atMs += moveCost(cell, cell)! * msPerCost;
    return { q: cell.q, r: cell.r, atMs: Math.max(i, Math.round(atMs)) };
  });
}

export function vaultCapacity(data: GameData, level: number): number {
  const v = data.logistics.vault;
  return v.baseCapacity * v.capacityGrowth ** (level - 1);
}

export function vaultUpgradeCost(data: GameData, targetLevel: number): Resources {
  const v = data.logistics.vault;
  return mapResources((kind) => Math.round(v.upgradeCost[kind] * v.costGrowth ** (targetLevel - 2)));
}

export function vaultUpgradeMs(data: GameData, targetLevel: number, worldSpeed: number): number {
  const v = data.logistics.vault;
  return Math.round((v.upgradeSeconds * v.timeGrowth ** (targetLevel - 2) * 1000) / worldSpeed);
}

// Puts `load` into stores holding `amounts` up to `capacity` each; returns
// what fits and what is left over.
export function store(amounts: Resources, capacity: number, load: Resources): { amounts: Resources; leftover: Resources } {
  const stored = mapResources((kind) => Math.min(load[kind], Math.max(0, capacity - amounts[kind])));
  return {
    amounts: mapResources((kind) => amounts[kind] + stored[kind]),
    leftover: mapResources((kind) => load[kind] - stored[kind]),
  };
}

// Takes up to `request` out of `amounts`.
export function withdraw(amounts: Resources, request: Resources): { amounts: Resources; taken: Resources } {
  const taken = mapResources((kind) => Math.min(request[kind], amounts[kind]));
  return { amounts: mapResources((kind) => amounts[kind] - taken[kind]), taken };
}

// A delivery into a village's stores: settles the ledger, fills up to its
// capacity and returns what didn't fit.
export function receive(ledger: ResourceLedger, at: Date, load: Resources): { ledger: ResourceLedger; leftover: Resources } {
  const settled = settle(ledger, at);
  const stored = mapResources((kind) => Math.min(load[kind], Math.max(0, settled.capacity[kind] - settled.amounts[kind])));
  return {
    ledger: { ...settled, amounts: mapResources((kind) => settled.amounts[kind] + stored[kind]) },
    leftover: mapResources((kind) => load[kind] - stored[kind]),
  };
}
