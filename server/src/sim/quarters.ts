// Armies quartered in a settlement, fort or supply point (data/armies.json
// `quarters`): the place feeds them `quarters.upkeep` of their upkeep from
// its granary, and their own grain keeps. It feeds them down to its floor:
// forts and supply points to the last grain, settlements to
// `quarters.settlementFloor` of their grain storage, unless the owner sets
// another floor. An army setting off from such a place fills up to its full
// supply, down to the same floor.
import type { GameData } from '../data/index.js';
import { armyUpkeep } from './supply.js';
import type { Units } from './training.js';

const HOUR_MS = 3_600_000;

// How low a settlement's grain may fall for armies: its own floor, else
// the default share of its grain storage.
export function settlementFloor(data: GameData, floor: number | null | undefined, grainCapacity: number): number {
  return floor ?? Math.floor(grainCapacity * data.armies.quarters.settlementFloor);
}

// How low a fort's or supply point's grain may fall for armies.
export function storeFloor(floor: number | null | undefined): number {
  return floor ?? 0;
}

// What a place can give armies: its grain above the floor.
export function spareGrain(grain: number, floor: number): number {
  return Math.max(0, grain - floor);
}

// Grain a place feeds an army quartered in it per real hour.
export function quarterRate(data: GameData, units: Units, worldSpeed: number): number {
  return armyUpkeep(data, units, worldSpeed) * data.armies.quarters.upkeep;
}

// What a quartered army has eaten of the place's grain since `since`.
export function quarterOwed(data: GameData, units: Units, since: Date, at: Date, worldSpeed: number): number {
  return (quarterRate(data, units, worldSpeed) * Math.max(0, at.getTime() - since.getTime())) / HOUR_MS;
}

// A game hour in real ms: how often a quartered army's place is charged.
export function quarterTickMs(worldSpeed: number): number {
  return Math.round(HOUR_MS / worldSpeed);
}
