// Difficulty presets and group power (PLAN.md §7.6), and the group's quiet
// hours for horde arrivals (§7.2). Numbers in data/difficulty.json.
import type { Difficulty, DifficultyPreset, GameData } from '../data/index.js';
import { inQuietHours } from './notifications.js';

const MS_PER_MINUTE = 60_000;
const MINUTES_PER_DAY = 1440;

export function presetOf(data: GameData, difficulty: Difficulty): DifficultyPreset {
  return data.difficulty.presets[difficulty];
}

export interface GroupPower {
  readonly players: number;
  readonly villages: number;
  // The collective power of every fighting unit the group has (home, away,
  // training): unitPower summed.
  readonly armyPower: number;
  readonly waveIndex: number;
  // Stages of the Kalinov Bridge standing.
  readonly bridgeStages?: number;
}

// How much bigger than its base size a wave comes: the preset's scale,
// raised by villages beyond one per player and by an army stronger than
// the expected curve, between the preset's floor and cap.
export function waveFactor(data: GameData, difficulty: Difficulty, power: GroupPower): number {
  const p = presetOf(data, difficulty);
  const bridge = 1 + data.bridge.powerPerStage * (power.bridgeStages ?? 0);
  const factor = p.waveScale * strength(data, difficulty, power) * bridge;
  return Math.min(p.maxFactor, Math.max(p.floor, factor));
}

// How much stronger than expected the group is: 1, plus powerWeight for
// every village beyond one per player and for every share of army power
// beyond the expected curve.
function strength(data: GameData, difficulty: Difficulty, power: GroupPower): number {
  const p = presetOf(data, difficulty);
  const players = Math.max(1, power.players);
  const extraVillages = Math.max(0, power.villages / players - 1);
  const expected = players * data.difficulty.power.perPlayer * (1 + data.difficulty.power.growthPerWave * power.waveIndex);
  const extraArmy = Math.max(0, power.armyPower / expected - 1);
  return 1 + p.powerWeight * (extraVillages + extraArmy);
}

// How much bigger camps rising after a wave come (not the starter camps):
// the group's strength, at least 1, at most the preset's maxFactor.
export function campFactor(data: GameData, difficulty: Difficulty, power: GroupPower): number {
  return Math.min(presetOf(data, difficulty).maxFactor, Math.max(1, strength(data, difficulty, power)));
}

// One unit's share of the group's collective power (difficulty.json power.weights).
export function unitPower(data: GameData, unit: string): number {
  const def = data.units.units[unit];
  const w = data.difficulty.power.weights;
  return def ? def.attack * w.attack + def.defense * w.defense + def.health * w.health : 0;
}

// Camps rising when a wave ends: the base count times the preset's rate,
// the fraction settled by a roll.
export function campsPerWave(data: GameData, difficulty: Difficulty, roll: number): number {
  const exact = data.camps.spawn.perWave * presetOf(data, difficulty).campRate;
  return Math.floor(exact) + (roll < exact - Math.floor(exact) ? 1 : 0);
}

export interface QuietWindow {
  // Minutes after the group's local midnight.
  readonly start: number;
  readonly end: number;
  readonly utcOffsetMinutes: number;
}

// Hordes hold off while the group sleeps: an arrival inside the window
// moves to its end.
export function afterQuiet(window: QuietWindow | null, at: Date): Date {
  if (!window) return at;
  const prefs = { quietStart: window.start, quietEnd: window.end, utcOffsetMinutes: window.utcOffsetMinutes, digestHour: 0, pushOff: [] };
  if (!inQuietHours(at, prefs)) return at;
  const minute = Math.floor(at.getTime() / MS_PER_MINUTE);
  const local = (((minute + window.utcOffsetMinutes) % MINUTES_PER_DAY) + MINUTES_PER_DAY) % MINUTES_PER_DAY;
  let wait = window.end - local;
  if (wait <= 0) wait += MINUTES_PER_DAY;
  return new Date((minute + wait) * MS_PER_MINUTE);
}
