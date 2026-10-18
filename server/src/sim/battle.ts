// Battle resolution (PLAN.md §6.5). A battle is a series of rounds; in each
// round both sides deal damage at once, spread over the enemy's unit types
// by their share of its numbers. Everything random comes from a seeded RNG,
// so a battle replays the same way.
import type { GameData, Stance, UnitFamily } from '../data/index.js';
import type { Front } from './mapgen.js';
import { mapResources, type Resources } from './resources.js';
import { createRng } from './rng.js';
import type { Units } from './training.js';
import { attackFactor, bonus, defenseFactor, type Bonuses } from './research.js';

export interface UnitStats {
  readonly attack: number;
  readonly defense: number;
  readonly family: UnitFamily;
}

export interface Side {
  readonly units: Units;
  readonly stance: Stance;
  readonly stats: (unit: string) => UnitStats;
  // Fighting at home (behind your own village) toughens defense.
  readonly home: boolean;
}

export interface RoundResult {
  readonly attackerLosses: Record<string, number>;
  readonly defenderLosses: Record<string, number>;
}

export type Outcome = 'ongoing' | 'defended' | 'raided';

// However steady a faction, a horde breaks once this share of it has fallen.
const MAX_RETREAT_AT = 0.95;

export function total(units: Units): number {
  return Object.values(units).reduce((sum, n) => sum + n, 0);
}

// The player's units, with their research: `home` adds the bonus for
// defending one's own village.
export function playerStats(data: GameData, bonuses: Bonuses = {}, home = false): (unit: string) => UnitStats {
  return (unit) => {
    const def = data.units.units[unit] ?? { attack: 0, defense: 1, family: 'infantry' as const };
    return {
      family: def.family,
      attack: def.attack * attackFactor(bonuses, def.family),
      defense: def.defense * defenseFactor(bonuses, def.family, home),
    };
  };
}

export function enemyStats(data: GameData, front: Front): (unit: string) => UnitStats {
  const units = data.enemies.fronts[front]?.units ?? {};
  return (unit) => units[unit] ?? { attack: 0, defense: 1, family: 'infantry' };
}

export function battleRng(seed: number, battleId: number, round: number): () => number {
  return createRng((seed ^ Math.imul(battleId + 1, 0xcc9e2d51) ^ Math.imul(round + 1, 0x1b873593)) >>> 0);
}

// Kills `from` inflicts on `to` this round, by unit type.
function kills(data: GameData, from: Side, to: Side, rng: () => number): Record<string, number> {
  const { battle } = data;
  const targets = Object.entries(to.units).filter(([, n]) => n > 0);
  const targetTotal = targets.reduce((sum, [, n]) => sum + n, 0);
  const result: Record<string, number> = {};
  if (targetTotal === 0) return result;

  const fromStance = battle.stances[from.stance];
  const toStance = battle.stances[to.stance];
  const matchup = battle.matchups[from.stance]?.[to.stance] ?? 1;
  for (const [target, targetCount] of targets) {
    const stats = to.stats(target);
    let damage = 0;
    for (const [unit, count] of Object.entries(from.units)) {
      if (count <= 0) continue;
      const attacker = from.stats(unit);
      const counter = battle.counters[attacker.family]?.[stats.family] ?? 1;
      damage += count * attacker.attack * fromStance.attack * matchup * counter;
    }
    const share = targetCount / targetTotal;
    const variance = 1 + battle.variance * (rng() * 2 - 1);
    const toughness = Math.max(1, stats.defense) * toStance.defense * (to.home ? battle.homeBonus : 1);
    const expected = (damage * share * variance * battle.casualtyScale) / toughness;
    // Round randomly so small fights still take losses on average.
    const whole = Math.floor(expected) + (rng() < expected - Math.floor(expected) ? 1 : 0);
    const dead = Math.min(targetCount, whole);
    if (dead > 0) result[target] = dead;
  }
  return result;
}

export function resolveRound(data: GameData, attacker: Side, defender: Side, rng: () => number): RoundResult {
  // Simultaneous: both sides strike with the numbers they had at the start.
  return { attackerLosses: kills(data, defender, attacker, rng), defenderLosses: kills(data, attacker, defender, rng) };
}

export function subtractUnits(units: Units, losses: Units): Record<string, number> {
  const left: Record<string, number> = {};
  for (const [unit, count] of Object.entries(units)) {
    const remaining = count - (losses[unit] ?? 0);
    if (remaining > 0) left[unit] = remaining;
  }
  return left;
}

// `nerve` scales the stance's retreat threshold (a faction's discipline).
function broken(data: GameData, stance: Stance, initial: Units, now: Units, nerve = 1): boolean {
  const base = data.battle.stances[stance].retreatAt;
  const retreatAt = base === null ? null : Math.min(MAX_RETREAT_AT, base * nerve);
  const start = total(initial);
  return retreatAt !== null && start > 0 && (start - total(now)) / start >= retreatAt;
}

// Checked after each round. The defenders hold if both sides fall at once.
export function battleOutcome(
  data: GameData,
  input: {
    round: number;
    attackerStance: Stance;
    attackerInitial: Units;
    attackerNow: Units;
    defenderStance: Stance;
    defenderInitial: Units;
    defenderNow: Units;
    attackerNerve?: number;
  },
): Outcome {
  if (total(input.attackerNow) === 0) return 'defended';
  if (total(input.defenderNow) === 0) return 'raided';
  if (broken(data, input.attackerStance, input.attackerInitial, input.attackerNow, input.attackerNerve)) return 'defended';
  if (broken(data, input.defenderStance, input.defenderInitial, input.defenderNow)) return 'raided';
  return input.round >= data.battle.maxRounds ? 'defended' : 'ongoing';
}

// What a victorious horde carries off: a share of the stores, smaller the
// more of the horde fell. `bonuses` are the raided player's (hidden
// cellars); `lootFactor` is the horde's faction's greed.
export function raidLoot(
  data: GameData,
  amounts: Resources,
  attackerInitial: Units,
  attackerNow: Units,
  bonuses: Bonuses = {},
  lootFactor = 1,
): Resources {
  const start = total(attackerInitial);
  const surviving = start > 0 ? total(attackerNow) / start : 0;
  const share = Math.min(1, data.battle.raidShare * lootFactor * Math.max(0, 1 + bonus(bonuses, 'lootTaken')));
  return mapResources((kind) => Math.floor(amounts[kind] * share * surviving + 1e-9));
}

export function roundMs(data: GameData, worldSpeed: number): number {
  return Math.round((data.battle.roundMinutes * 60_000) / worldSpeed);
}

// A wave's stance, weighted by its front's temperament.
export function waveStance(data: GameData, front: Front, seed: number, index: number): Stance {
  const weights = Object.entries(data.enemies.fronts[front]?.stances ?? {}) as [Stance, number][];
  if (weights.length === 0) return 'balanced';
  const totalWeight = weights.reduce((sum, [, w]) => sum + w, 0);
  let roll = createRng((seed ^ Math.imul(index + 1, 0x27d4eb2f) ^ 0x57a7) >>> 0)() * totalWeight;
  for (const [stance, weight] of weights) {
    if ((roll -= weight) < 0) return stance;
  }
  return weights.at(-1)![0];
}
