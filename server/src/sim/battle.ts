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
  // Armor: it turns aside damage, less of it the more there is.
  readonly defense: number;
  // How much damage it takes to fell one.
  readonly health: number;
  readonly family: UnitFamily;
  // The unit's own counters, in place of its family's.
  readonly counters?: Partial<Record<UnitFamily, number>>;
}

export interface Side {
  readonly units: Units;
  readonly stance: Stance;
  readonly stats: (unit: string) => UnitStats;
  // Fighting at home (behind your own village) toughens defense.
  readonly home: boolean;
  // The side's forces when they fight apart, each in its own stance (a
  // village's garrison, each army): `units` and `stance` are then unused.
  readonly groups?: readonly Group[];
}

export interface Group {
  readonly units: Units;
  readonly stance: Stance;
  // Its own stats in place of the side's.
  readonly stats?: (unit: string) => UnitStats;
}

export interface RoundResult {
  readonly attackerLosses: Record<string, number>;
  readonly defenderLosses: Record<string, number>;
  // By group, when the defenders fight in groups.
  readonly defenderGroupLosses?: Record<string, number>[];
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
    const def = data.units.units[unit] ?? { attack: 0, defense: 1, health: 1, family: 'infantry' as const };
    return {
      family: def.family,
      attack: def.attack * attackFactor(bonuses, def.family),
      defense: def.defense * defenseFactor(bonuses, def.family, home),
      health: def.health,
      ...('counters' in def && def.counters ? { counters: def.counters } : {}),
    };
  };
}

export function enemyStats(data: GameData, front: Front): (unit: string) => UnitStats {
  const units = data.enemies.fronts[front]?.units ?? {};
  return (unit) => units[unit] ?? { attack: 0, defense: 1, health: 1, family: 'infantry' };
}

export function battleRng(seed: number, battleId: number, round: number): () => number {
  return createRng((seed ^ Math.imul(battleId + 1, 0xcc9e2d51) ^ Math.imul(round + 1, 0x1b873593)) >>> 0);
}

function groupsOf(side: Side): Group[] {
  return side.groups ? [...side.groups] : [{ units: side.units, stance: side.stance }];
}

// Kills `from` inflicts on `to` this round, by unit type, for each of
// `to`'s groups.
function kills(data: GameData, from: Side, to: Side, rng: () => number): Record<string, number>[] {
  const { battle } = data;
  const strikers = groupsOf(from);
  const groups = groupsOf(to);
  const result: Record<string, number>[] = groups.map(() => ({}));
  const targets = groups.flatMap((g, i) => Object.entries(g.units).filter(([, n]) => n > 0).map(([unit, n]) => ({ i, unit, n })));
  const targetTotal = targets.reduce((sum, t) => sum + t.n, 0);
  if (targetTotal === 0) return result;

  for (const { i, unit: target, n: targetCount } of targets) {
    const group = groups[i]!;
    const stats = (group.stats ?? to.stats)(target);
    let damage = 0;
    for (const striker of strikers) {
      const fromStance = battle.stances[striker.stance];
      const matchup = battle.matchups[striker.stance]?.[group.stance] ?? 1;
      for (const [unit, count] of Object.entries(striker.units)) {
        if (count <= 0) continue;
        const attacker = (striker.stats ?? from.stats)(unit);
        const counter = (attacker.counters ?? battle.counters[attacker.family])?.[stats.family] ?? 1;
        damage += count * attacker.attack * fromStance.attack * matchup * counter;
      }
    }
    const share = targetCount / targetTotal;
    const variance = 1 + battle.variance * (rng() * 2 - 1);
    // Defense is armor, as in an RPG: k / (k + armor) of the damage lands.
    // Each of the target's health that lands (hardened by its stance and by
    // fighting at home) fells one.
    const lands = battle.armorConstant / (battle.armorConstant + Math.max(0, stats.defense));
    const toughness = Math.max(1, stats.health) * battle.stances[group.stance].defense * (to.home ? battle.homeBonus : 1);
    const expected = (damage * share * variance * battle.casualtyScale * lands) / toughness;
    // Round randomly so small fights still take losses on average.
    const whole = Math.floor(expected) + (rng() < expected - Math.floor(expected) ? 1 : 0);
    const dead = Math.min(targetCount, whole);
    if (dead > 0) result[i]![target] = (result[i]![target] ?? 0) + dead;
  }
  return result;
}

function merged(losses: readonly Record<string, number>[]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const l of losses) for (const [unit, n] of Object.entries(l)) out[unit] = (out[unit] ?? 0) + n;
  return out;
}

export function resolveRound(data: GameData, attacker: Side, defender: Side, rng: () => number): RoundResult {
  // Simultaneous: both sides strike with the numbers they had at the start.
  const attackerLosses = merged(kills(data, defender, attacker, rng));
  const byGroup = kills(data, attacker, defender, rng);
  return { attackerLosses, defenderLosses: merged(byGroup), ...(defender.groups ? { defenderGroupLosses: byGroup } : {}) };
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
export function broken(data: GameData, stance: Stance, initial: Units, now: Units, nerve = 1): boolean {
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
    // Defenders fighting in groups, each breaking on its own (in place of
    // defenderStance and defenderInitial): they lose once none still stands.
    defenderGroups?: readonly { stance: Stance; initial: Units; now: Units }[];
  },
): Outcome {
  if (total(input.attackerNow) === 0) return 'defended';
  if (total(input.defenderNow) === 0) return 'raided';
  if (broken(data, input.attackerStance, input.attackerInitial, input.attackerNow, input.attackerNerve)) return 'defended';
  if (input.defenderGroups) {
    if (input.defenderGroups.every((g) => total(g.now) === 0 || broken(data, g.stance, g.initial, g.now))) return 'raided';
  } else if (broken(data, input.defenderStance, input.defenderInitial, input.defenderNow)) return 'raided';
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

// A round takes roundMinutes of real time, whatever the world's speed, so
// reinforcements have time to come.
export function roundMs(data: GameData): number {
  return Math.round(data.battle.roundMinutes * 60_000);
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
