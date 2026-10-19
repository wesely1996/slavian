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
  // Total attack of every fighting unit the group has (home, away, training).
  readonly armyAttack: number;
  readonly waveIndex: number;
}

// How much bigger than its base size a wave comes: the preset's scale,
// raised by villages beyond one per player and by an army stronger than
// the expected curve, between the preset's floor and cap.
export function waveFactor(data: GameData, difficulty: Difficulty, power: GroupPower): number {
  const p = presetOf(data, difficulty);
  const players = Math.max(1, power.players);
  const extraVillages = Math.max(0, power.villages / players - 1);
  const expected = players * data.difficulty.power.attackPerPlayer * (1 + data.difficulty.power.growthPerWave * power.waveIndex);
  const extraArmy = Math.max(0, power.armyAttack / expected - 1);
  const factor = p.waveScale * (1 + p.powerWeight * (extraVillages + extraArmy));
  return Math.min(p.maxFactor, Math.max(p.floor, factor));
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
  const prefs = { quietStart: window.start, quietEnd: window.end, utcOffsetMinutes: window.utcOffsetMinutes, digestHour: 0 };
  if (!inQuietHours(at, prefs)) return at;
  const minute = Math.floor(at.getTime() / MS_PER_MINUTE);
  const local = (((minute + window.utcOffsetMinutes) % MINUTES_PER_DAY) + MINUTES_PER_DAY) % MINUTES_PER_DAY;
  let wait = window.end - local;
  if (wait <= 0) wait += MINUTES_PER_DAY;
  return new Date((minute + wait) * MS_PER_MINUTE);
}
