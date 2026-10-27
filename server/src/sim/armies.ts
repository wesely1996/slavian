// Armies: troops out of their village, marching to another village to
// support it, reinforce a battle there, or harass the horde.
import type { GameData } from '../data/index.js';
import { RuleError } from '../errors.js';
import { hexToPixel, type Hex } from './hex.js';
import type { Units } from './training.js';

// `garrison`: marching into one of its owner's villages to join the garrison.
export type ArmyOrders = 'support' | 'reinforce' | 'harass' | 'hold' | 'clear' | 'explore' | 'garrison';
const FIGHTERS = new Set(['infantry', 'archers', 'cavalry']);

export function total(units: Units): number {
  return Object.values(units).reduce((sum, n) => sum + n, 0);
}

// Units that fight in the field (not scouts or settlers).
export function fighters(data: GameData, units: Units): Record<string, number> {
  const out: Record<string, number> = {};
  for (const [unit, n] of Object.entries(units)) {
    const def = data.units.units[unit];
    if (def && FIGHTERS.has(def.family) && unit !== 'settler' && n > 0) out[unit] = n;
  }
  return out;
}

// Hexes per hour on plains: the slowest unit sets the pace.
export function armySpeed(data: GameData, units: Units): number {
  const speeds = Object.keys(units).filter((u) => (units[u] ?? 0) > 0).map((u) => data.units.units[u]?.speed ?? 1);
  return speeds.length ? Math.min(...speeds) : 1;
}

export function cavalryShare(data: GameData, units: Units): number {
  const all = total(units);
  if (all === 0) return 0;
  const cavalry = Object.entries(units).reduce((sum, [u, n]) => sum + (data.units.units[u]?.family === 'cavalry' ? n : 0), 0);
  return cavalry / all;
}

// Who may go: fighters, and scouts too when exploring a site.
function marches(data: GameData, unit: string, orders: ArmyOrders): boolean {
  return !!fighters(data, { [unit]: 1 })[unit] || (orders === 'explore' && data.units.units[unit]?.family === 'scout');
}

// Checks an army about to set out.
export function validateArmy(data: GameData, units: Units, orders: ArmyOrders): Record<string, number> {
  for (const [unit, n] of Object.entries(units)) {
    if (!Number.isInteger(n) || n < 0) throw new RuleError('Troop counts are whole numbers');
    if (n > 0 && !marches(data, unit, orders)) throw new RuleError(`${data.units.units[unit]?.name ?? unit} don't march with armies`);
  }
  const army = Object.fromEntries(Object.entries(units).filter(([unit, n]) => n > 0 && marches(data, unit, orders)));
  if (total(army) === 0) throw new RuleError('Send at least one soldier');
  if (orders === 'harass' && cavalryShare(data, army) < data.armies.harass.minCavalryShare) {
    throw new RuleError(`Harassing takes mostly cavalry (${Math.round(data.armies.harass.minCavalryShare * 100)}% or more)`);
  }
  return army;
}

// `share` of each fighting unit, rounded down.
export function shareOf(data: GameData, units: Units, share: number): Record<string, number> {
  const out: Record<string, number> = {};
  for (const [unit, n] of Object.entries(fighters(data, units))) {
    const part = Math.floor(n * share);
    if (part > 0) out[unit] = part;
  }
  return out;
}

// Degrees between the directions two forces come from, seen from `at`.
export function approachAngle(at: Hex, a: Hex, b: Hex): number {
  const o = hexToPixel(at, 1);
  const pa = hexToPixel(a, 1);
  const pb = hexToPixel(b, 1);
  const ax = pa.x - o.x;
  const ay = pa.y - o.y;
  const bx = pb.x - o.x;
  const by = pb.y - o.y;
  const la = Math.hypot(ax, ay);
  const lb = Math.hypot(bx, by);
  if (la === 0 || lb === 0) return 0;
  const cos = Math.max(-1, Math.min(1, (ax * bx + ay * by) / (la * lb)));
  return (Math.acos(cos) * 180) / Math.PI;
}

// The first-round bonus of an army joining a battle: harassers always strike
// hard; reinforcements get a pincer bonus when they come from another side.
export function joinBonus(
  data: GameData,
  input: { orders: ArmyOrders; armySize: number; hordeSize: number; angle: number },
): number {
  if (input.hordeSize <= 0) return 0;
  const ratio = input.armySize / input.hordeSize;
  if (input.orders === 'harass') return Math.min(data.armies.harass.maxBonus, data.armies.harass.scale * ratio);
  if (input.angle < data.armies.pincer.minAngle) return 0;
  return Math.min(data.armies.pincer.maxBonus, data.armies.pincer.scale * ratio);
}

// Splits a side's losses between the forces that made it up, in proportion
// to how many of each unit they brought (largest remainder, deterministic).
export function splitLosses(losses: Units, forces: readonly Units[]): Record<string, number>[] {
  const out = forces.map(() => ({}) as Record<string, number>);
  for (const [unit, lost] of Object.entries(losses)) {
    const counts = forces.map((f) => f[unit] ?? 0);
    const all = counts.reduce((a, b) => a + b, 0);
    if (lost <= 0 || all <= 0) continue;
    const take = Math.min(lost, all);
    const exact = counts.map((c) => (take * c) / all);
    const floors = exact.map((x, i) => Math.min(counts[i]!, Math.floor(x)));
    let left = take - floors.reduce((a, b) => a + b, 0);
    const order = exact.map((x, i) => [x - Math.floor(x), i] as const).sort((a, b) => b[0] - a[0] || a[1] - b[1]);
    for (const [, i] of order) {
      if (left <= 0) break;
      if (floors[i]! < counts[i]!) {
        floors[i]! += 1;
        left -= 1;
      }
    }
    floors.forEach((n, i) => {
      if (n > 0) out[i]![unit] = n;
    });
  }
  return out;
}

export function addUnits(a: Units, b: Units): Record<string, number> {
  const sum: Record<string, number> = { ...a };
  for (const [unit, n] of Object.entries(b)) sum[unit] = (sum[unit] ?? 0) + n;
  return sum;
}
