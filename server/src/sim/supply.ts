// Field armies carry their own grain (data/armies.json, `supply` and
// `attrition`). An army's supply is the grain it had at `supplyAt`; it eats
// its full upkeep from it, lazily. Out of food it marches slower, then
// loses men every few hours, and in the end is lost altogether.
import type { GameData } from '../data/index.js';
import { upkeepPerHour, type Units } from './training.js';

const HOUR_MS = 3_600_000;

export interface Supplied {
  readonly units: Units;
  // Grain carried at supplyAt.
  readonly supply: number;
  readonly supplyAt: Date;
  // When the food ran out, once that is settled (null: fed, or not yet known).
  readonly hungrySince: Date | null;
}

// Grain an army eats per real hour.
export function armyUpkeep(data: GameData, units: Units, worldSpeed: number): number {
  return upkeepPerHour(data, units, worldSpeed);
}

// Grain for `supply.hours` game hours of an army's upkeep.
export function fullSupply(data: GameData, units: Units): number {
  return upkeepPerHour(data, units, 1) * data.armies.supply.hours;
}

export function supplyLeft(data: GameData, army: Supplied, at: Date, worldSpeed: number): number {
  const rate = armyUpkeep(data, army.units, worldSpeed);
  return Math.max(0, army.supply - (rate * (at.getTime() - army.supplyAt.getTime())) / HOUR_MS);
}

// When the food runs (or ran) out at the present rate (null: it eats nothing).
export function outOfFoodAt(data: GameData, army: Supplied, worldSpeed: number): Date | null {
  if (army.hungrySince) return army.hungrySince;
  const rate = armyUpkeep(data, army.units, worldSpeed);
  if (rate <= 0) return null;
  return new Date(army.supplyAt.getTime() + Math.ceil((army.supply * HOUR_MS) / rate));
}

// Game hours an army has gone without food by `at` (0: still fed).
export function hungerHours(data: GameData, army: Supplied, at: Date, worldSpeed: number): number {
  const out = outOfFoodAt(data, army, worldSpeed);
  if (!out || out > at) return 0;
  return ((at.getTime() - out.getTime()) * worldSpeed) / HOUR_MS;
}

// Whether an army is out of food at `at` (it marches slower).
export function hungry(data: GameData, army: Supplied, at: Date, worldSpeed: number): boolean {
  const out = outOfFoodAt(data, army, worldSpeed);
  return out !== null && out <= at;
}

// The army's supply as of `at`: before its numbers change, and before
// grain is added. Keeps when the food ran out.
export function settleSupply<A extends Supplied>(data: GameData, army: A, at: Date, worldSpeed: number): A {
  const out = outOfFoodAt(data, army, worldSpeed);
  const hungrySince = out && out <= at ? out : null;
  return { ...army, supply: supplyLeft(data, army, at, worldSpeed), supplyAt: at, hungrySince };
}

// Grain added to an army's supply (settled first): it is fed again.
export function addSupply<A extends Supplied>(data: GameData, army: A, grain: number, at: Date, worldSpeed: number): A {
  const settled = settleSupply(data, army, at, worldSpeed);
  if (grain <= 0) return settled;
  return { ...settled, supply: settled.supply + grain, hungrySince: null };
}

// How much more the army can take on: up to its full supply.
export function supplyRoom(data: GameData, army: Supplied, at: Date, worldSpeed: number): number {
  return Math.max(0, fullSupply(data, army.units) - supplyLeft(data, army, at, worldSpeed));
}

// When hunger starts to kill (`start`, then every `tick`) and when the army
// is lost (`end`), in ms; null while it eats nothing.
function hungerTimes(data: GameData, army: Supplied, worldSpeed: number): { start: number; end: number; tick: number } | null {
  const out = outOfFoodAt(data, army, worldSpeed);
  if (!out) return null;
  const { lossAfterHours, checkHours, lostAfterHours } = data.armies.attrition;
  return {
    start: out.getTime() + Math.round((lossAfterHours * HOUR_MS) / worldSpeed),
    end: out.getTime() + Math.round((lostAfterHours * HOUR_MS) / worldSpeed),
    tick: Math.round((checkHours * HOUR_MS) / worldSpeed),
  };
}

// The next time hunger does something to the army after `at` (losses, or
// the end): null while it eats nothing.
export function nextHungerCheck(data: GameData, army: Supplied, at: Date, worldSpeed: number): Date | null {
  const times = hungerTimes(data, army, worldSpeed);
  if (!times) return null;
  const { start, end, tick } = times;
  let next = start;
  if (at.getTime() >= start) next = start + (Math.floor((at.getTime() - start) / tick) + 1) * tick;
  return new Date(Math.min(next, end));
}

// What hunger does at `at`: losses to each unit, or the end of the army.
export function hungerStrikes(data: GameData, army: Supplied, at: Date, worldSpeed: number): { lost: boolean; losses: Record<string, number> } {
  const times = hungerTimes(data, army, worldSpeed);
  const losses: Record<string, number> = {};
  if (!times || at.getTime() < times.start) return { lost: false, losses };
  if (at.getTime() >= times.end) return { lost: true, losses: { ...army.units } };
  for (const [unit, n] of Object.entries(army.units)) if (n > 0) losses[unit] = Math.min(n, Math.ceil(n * data.armies.attrition.lossShare));
  return { lost: false, losses };
}

// How fast an army marches: slower out of food.
export function supplySpeedFactor(data: GameData, army: Supplied | null, at: Date, worldSpeed: number): number {
  return army && hungry(data, army, at, worldSpeed) ? data.armies.attrition.slowFactor : 1;
}
