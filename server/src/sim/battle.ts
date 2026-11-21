// Battle resolution (PLAN.md §6.5). A battle is a series of rounds; in each
// round both sides deal damage at once, spread over the enemy's unit types
// by their share of its numbers. Everything random comes from a seeded RNG,
// so a battle replays the same way.
import { AFFLICTIONS, type Affliction, type GameData, type Stance, type UnitFamily } from '../data/index.js';
import type { Front } from './mapgen.js';
import { groundFactors, playerShares, type Ground, type TerrainShares } from './ground.js';
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
  // What its blows inflict (battle.json afflictions).
  readonly inflicts?: readonly Affliction[] | undefined;
  // Its strength on some ground beyond its family's (battle.json terrain):
  // its own, and its clan's for a player's unit.
  readonly terrain?: TerrainShares | undefined;
}

// What burns and poisons a side carries into the next round
// (battle.json afflictions): the burning damage owed to it in each of the
// rounds to come, and how many more rounds it fights poisoned.
export interface SideAfflictions {
  readonly burn: readonly number[];
  readonly poisoned: number;
}

export interface Afflictions {
  readonly attacker: SideAfflictions;
  readonly defender: SideAfflictions;
}

export const NO_AFFLICTIONS: Afflictions = { attacker: { burn: [], poisoned: 0 }, defender: { burn: [], poisoned: 0 } };

// A battle's setup with the afflictions the round left (none kept once
// nothing burns or poisons); the same object when nothing changed.
export function withAfflictions<T extends { afflictions?: Afflictions }>(setup: T, next: Afflictions): T {
  if (afflicted(next)) return { ...setup, afflictions: next };
  if (!setup.afflictions) return setup;
  const { afflictions: _gone, ...rest } = setup;
  return rest as T;
}

// Whether anything still burns or poisons either side.
export function afflicted(a: Afflictions | undefined): boolean {
  return !!a && [a.attacker, a.defender].some((side) => side.burn.length > 0 || side.poisoned > 0);
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
  // Its champions, when it fights as one (see Group).
  readonly champions?: readonly Champion[];
}

// A hero or general fighting in the ranks: one mighty warrior who strikes
// with its attack and, struck down, falls (heroes.json champion).
export interface Champion {
  // 'hero' or 'general'.
  readonly id: string;
  readonly attack: number;
  readonly defense: number;
  readonly health: number;
}

export interface Group {
  readonly units: Units;
  readonly stance: Stance;
  // Its own stats in place of the side's.
  readonly stats?: (unit: string) => UnitStats;
  readonly champions?: readonly Champion[];
}

export interface RoundResult {
  readonly attackerLosses: Record<string, number>;
  readonly defenderLosses: Record<string, number>;
  // By group, when the defenders fight in groups.
  readonly defenderGroupLosses?: Record<string, number>[];
  // Champions struck down this round (their ids), by group (one group for
  // a side fighting as one).
  readonly attackerFallen: string[][];
  readonly defenderFallen: string[][];
  // What burns and poisons both sides carry into the next round.
  readonly afflictions: Afflictions;
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
      // The family's research and the unit's own forging (smithing.json) add up.
      attack: def.attack * (attackFactor(bonuses, def.family) + bonus(bonuses, `attack.unit.${unit}`)),
      defense: def.defense * (defenseFactor(bonuses, def.family, home) + bonus(bonuses, `defense.unit.${unit}`)),
      health: def.health * (1 + bonus(bonuses, `health.unit.${unit}`)),
      ...('counters' in def && def.counters ? { counters: def.counters } : {}),
      ...inflictsOf('inflicts' in def ? def.inflicts : undefined, bonuses, unit),
      ...terrainOf(playerShares('terrain' in def ? def.terrain : undefined, bonuses)),
    };
  };
}

// A unit's own afflictions and those forged for it (burn.unit.<id>, poison.unit.<id>).
function inflictsOf(own: readonly Affliction[] | undefined, bonuses: Bonuses, unit: string): { inflicts?: Affliction[] } {
  const inflicts = AFFLICTIONS.filter((a) => (own ?? []).includes(a) || bonus(bonuses, `${a}.unit.${unit}`) > 0);
  return inflicts.length > 0 ? { inflicts } : {};
}

function terrainOf(shares: TerrainShares | undefined): { terrain?: TerrainShares } {
  return shares && Object.keys(shares).length > 0 ? { terrain: shares } : {};
}

export function enemyStats(data: GameData, front: Front): (unit: string) => UnitStats {
  const units = data.enemies.fronts[front]?.units ?? {};
  return (unit) => units[unit] ?? { attack: 0, defense: 1, health: 1, family: 'infantry' };
}

export function battleRng(seed: number, battleId: number, round: number): () => number {
  return createRng((seed ^ Math.imul(battleId + 1, 0xcc9e2d51) ^ Math.imul(round + 1, 0x1b873593)) >>> 0);
}

function groupsOf(side: Side): Group[] {
  return side.groups ? [...side.groups] : [{ units: side.units, stance: side.stance, ...(side.champions ? { champions: side.champions } : {}) }];
}

// A champion as a target: one warrior of its own stats.
function championStats(c: Champion): UnitStats {
  return { attack: c.attack, defense: c.defense, health: c.health, family: 'infantry' };
}

// How `kills` finds each side: `weak` its attack or defense factor while
// poisoned, `burning` the burning damage owed to `to` this round.
interface Plight {
  fromWeak: number;
  toWeak: number;
  burning: number;
  // Where the battle is fought (battle.json terrain).
  ground?: Ground | undefined;
}

// Kills `from` inflicts on `to` this round, by unit type, for each of
// `to`'s groups, and the champions it strikes down there; the blows of its
// burning units (what will burn on), and whether a poisoner struck.
function kills(
  data: GameData,
  from: Side,
  to: Side,
  rng: () => number,
  plight: Plight,
): { losses: Record<string, number>[]; fallen: string[][]; burnHit: number; poisons: boolean } {
  const { battle } = data;
  const strikers = groupsOf(from);
  const groups = groupsOf(to);
  const result: Record<string, number>[] = groups.map(() => ({}));
  const fallen: string[][] = groups.map(() => []);
  const poisons = strikers.some((g) =>
    Object.entries(g.units).some(([unit, count]) => {
      const stats = (g.stats ?? from.stats)(unit);
      return count > 0 && stats.attack > 0 && (stats.inflicts ?? []).includes('poison');
    }),
  );
  let burnHit = 0;
  const targets: { i: number; unit: string; n: number; champion?: Champion }[] = [
    ...groups.flatMap((g, i) => Object.entries(g.units).filter(([, n]) => n > 0).map(([unit, n]) => ({ i, unit, n }))),
    // Champions stand among their men: each is one more to strike at.
    ...groups.flatMap((g, i) => (g.champions ?? []).map((c) => ({ i, unit: c.id, n: 1, champion: c }))),
  ];
  const targetTotal = targets.reduce((sum, t) => sum + t.n, 0);
  if (targetTotal === 0) return { losses: result, fallen, burnHit, poisons: false };
  // Wagons in a ring (units.json wagon; only a wagon fort's fight) stand as a
  // wall before their side's archers: the blows aimed at the archers fall on
  // the wagons, each kind by its share of them, while any stand.
  const weights = targets.map((t) => t.n);
  for (const i of groups.keys()) {
    const indexes = (pick: (t: (typeof targets)[number]) => boolean) => targets.flatMap((t, k) => (t.i === i && !t.champion && pick(t) ? [k] : []));
    const wagons = indexes((t) => data.units.units[t.unit]?.wagon === true);
    const shooters = indexes((t) => (groups[i]!.stats ?? to.stats)(t.unit).family === 'archers');
    if (wagons.length === 0 || shooters.length === 0) continue;
    const shield = shooters.reduce((sum, k) => sum + targets[k]!.n, 0);
    const wall = wagons.reduce((sum, k) => sum + targets[k]!.n, 0);
    for (const k of shooters) weights[k] = 0;
    for (const k of wagons) weights[k] = targets[k]!.n + (shield * targets[k]!.n) / wall;
  }

  // Attack is a range: each unit type strikes this round with its own roll.
  const rolled = strikers.map((striker) =>
    Object.fromEntries(Object.entries(striker.units).filter(([, count]) => count > 0).map(([unit]) => [unit, 1 + battle.statSpread * (rng() * 2 - 1)])),
  );
  for (const [k, { i, unit: target, n: targetCount, champion }] of targets.entries()) {
    // Behind a wall of wagons: nothing reaches them.
    if (weights[k] === 0) continue;
    const group = groups[i]!;
    const stats = champion ? championStats(champion) : (group.stats ?? to.stats)(target);
    let damage = 0;
    let burning = 0;
    for (const [s, striker] of strikers.entries()) {
      const fromStance = battle.stances[striker.stance];
      const matchup = battle.matchups[striker.stance]?.[group.stance] ?? 1;
      for (const [unit, count] of Object.entries(striker.units)) {
        if (count <= 0) continue;
        const attacker = (striker.stats ?? from.stats)(unit);
        const counter = (attacker.counters ?? battle.counters[attacker.family])?.[stats.family] ?? 1;
        const onGround = groundFactors(data, plight.ground, attacker.family, attacker.terrain).attack;
        const blow = count * attacker.attack * onGround * rolled[s]![unit]! * fromStance.attack * matchup * counter * plight.fromWeak;
        damage += blow;
        if ((attacker.inflicts ?? []).includes('burn')) burning += blow;
      }
      // Its champions strike too, at no family's weakness.
      for (const c of striker.champions ?? []) damage += c.attack * fromStance.attack * matchup * plight.fromWeak;
    }
    // What still burns from earlier rounds, spread like any blow.
    damage += plight.burning;
    const share = weights[k]! / targetTotal;
    burnHit += burning * share;
    // Defense is a range too: this target's roll for the round.
    const guard = 1 + battle.statSpread * (rng() * 2 - 1);
    // Defense is armor, as in an RPG: k / (k + armor) of the damage lands.
    // Each of the target's health that lands (hardened by its stance and by
    // fighting at home) fells one.
    const held = champion ? 1 : groundFactors(data, plight.ground, stats.family, stats.terrain).defense;
    const lands = battle.armorConstant / (battle.armorConstant + Math.max(0, stats.defense * held * plight.toWeak) * guard);
    const toughness = Math.max(1, stats.health) * battle.stances[group.stance].defense * (to.home ? battle.homeBonus : 1);
    const expected = (damage * share * battle.casualtyScale * lands) / toughness;
    // Round randomly so small fights still take losses on average.
    const whole = Math.floor(expected) + (rng() < expected - Math.floor(expected) ? 1 : 0);
    const dead = Math.min(targetCount, whole);
    if (dead > 0 && champion) fallen[i]!.push(champion.id);
    else if (dead > 0) result[i]![target] = (result[i]![target] ?? 0) + dead;
  }
  return { losses: result, fallen, burnHit, poisons };
}

function merged(losses: readonly Record<string, number>[]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const l of losses) for (const [unit, n] of Object.entries(l)) out[unit] = (out[unit] ?? 0) + n;
  return out;
}

// What a side carries into the next round: the burning owed it moves a
// round on and this round's burning blows add `share` of themselves to each
// of the next `rounds`; a poisoner's blow poisons it afresh.
function carried(data: GameData, now: SideAfflictions, burnHit: number, poisoned: boolean): SideAfflictions {
  const { burn, poison } = data.battle.afflictions;
  const owed = now.burn.slice(1);
  const added = burnHit * burn.share;
  if (added > 0) for (let k = 0; k < burn.rounds; k++) owed[k] = (owed[k] ?? 0) + added;
  return { burn: owed, poisoned: poisoned ? poison.rounds : Math.max(0, now.poisoned - 1) };
}

// `ground`: where the battle is fought (battle.json terrain); none for a
// fight beyond the map's edge.
export function resolveRound(
  data: GameData,
  attacker: Side,
  defender: Side,
  rng: () => number,
  afflictions: Afflictions = NO_AFFLICTIONS,
  ground?: Ground,
): RoundResult {
  const weak = (side: SideAfflictions) => (side.poisoned > 0 ? data.battle.afflictions.poison.factor : 1);
  // Simultaneous: both sides strike with the numbers they had at the start.
  const struck = kills(data, defender, attacker, rng, { fromWeak: weak(afflictions.defender), toWeak: weak(afflictions.attacker), burning: afflictions.attacker.burn[0] ?? 0, ground });
  const byGroup = kills(data, attacker, defender, rng, { fromWeak: weak(afflictions.attacker), toWeak: weak(afflictions.defender), burning: afflictions.defender.burn[0] ?? 0, ground });
  return {
    afflictions: {
      attacker: carried(data, afflictions.attacker, struck.burnHit, struck.poisons),
      defender: carried(data, afflictions.defender, byGroup.burnHit, byGroup.poisons),
    },
    attackerLosses: merged(struck.losses),
    defenderLosses: merged(byGroup.losses),
    ...(defender.groups ? { defenderGroupLosses: byGroup.losses } : {}),
    attackerFallen: struck.fallen,
    defenderFallen: byGroup.fallen,
  };
}

// A hero's or general's champion at `level` (heroes.json champion,
// generals.champion): its base stats, `growthPerLevel` more each level.
export function championOf(data: GameData, id: 'hero' | 'general', level: number): Champion {
  const c = id === 'hero' ? data.heroes.champion : data.heroes.generals.champion;
  const f = 1 + c.growthPerLevel * Math.max(0, level - 1);
  return { id, attack: c.attack * f, defense: c.defense * f, health: c.health * f };
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
