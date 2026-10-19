// Enemy heroes (PLAN.md M5 step 8): every front has one named leader at a
// time. They lead the front's hordes, grow from battles like player heroes
// (levels from experience, a skill each level, picked in the front's own
// order), make their hordes hit harder, hold longer and carry off more, and
// remember the village that last beat them. Numbers in data/leaders.json.
import type { GameData } from '../data/index.js';
import type { UnitStats } from './battle.js';
import { createRng } from './rng.js';

const MS_PER_HOUR = 3_600_000;

export interface LeaderState {
  readonly name: string;
  readonly level: number;
  readonly xp: number;
  readonly skills: Readonly<Record<string, number>>;
}

export interface LeaderEffects {
  readonly attack: number;
  readonly defense: number;
  readonly nerve: number;
  readonly loot: number;
}

// A new leader for `front`: a name not yet used in this world, at `level`
// (a rival rising after a fallen one starts higher).
export function newLeader(data: GameData, front: string, seed: number, used: readonly string[], level = 1): LeaderState {
  const names = data.leaders.fronts[front]!.names;
  const free = names.filter((n) => !used.includes(n));
  const pool = free.length ? free : names;
  const rng = createRng((seed ^ Math.imul(used.length + 1, 0x85ebca6b) ^ front.length * 0x27d4eb2f) >>> 0);
  const name = pool[Math.floor(rng() * pool.length)]!;
  let leader: LeaderState = { name, level: 1, xp: 0, skills: {} };
  while (leader.level < Math.min(level, data.leaders.maxLevel)) leader = levelUp(data, front, leader);
  return leader;
}

// The level a rival rises at after a leader of `fallenLevel` dies.
export function riseLevel(data: GameData, fallenLevel: number): number {
  return 1 + Math.floor(fallenLevel * data.leaders.riseShare);
}

// "Khan Konchak": the name in the rank its level has reached.
export function leaderTitle(data: GameData, front: string, leader: Pick<LeaderState, 'name' | 'level'>): string {
  const ranks = data.leaders.fronts[front]?.ranks ?? [{ minLevel: 1, title: '{name}' }];
  const rank = [...ranks].reverse().find((r) => leader.level >= r.minLevel) ?? ranks[0]!;
  return rank.title.replace('{name}', leader.name);
}

export function leaderXpToNext(data: GameData, level: number): number {
  const { base, growth } = data.leaders.levelXp;
  return Math.round(base * growth ** (level - 1));
}

export function gainLeaderXp(data: GameData, front: string, leader: LeaderState, xp: number): LeaderState {
  let next: LeaderState = { ...leader, xp: leader.xp + Math.max(0, Math.floor(xp)) };
  while (next.level < data.leaders.maxLevel && next.xp >= leaderXpToNext(data, next.level)) {
    next = levelUp(data, front, { ...next, xp: next.xp - leaderXpToNext(data, next.level) });
  }
  return next.level >= data.leaders.maxLevel ? { ...next, xp: 0 } : next;
}

// One level up, with the next skill in the front's order that isn't maxed.
function levelUp(data: GameData, front: string, leader: LeaderState): LeaderState {
  const level = leader.level + 1;
  const order = data.leaders.fronts[front]!.skills;
  let skills = leader.skills;
  for (let i = 0; i < order.length; i++) {
    const skill = order[(level - 2 + i) % order.length]!;
    const rank = skills[skill] ?? 0;
    if (rank < data.leaders.skills[skill]!.maxRank) {
      skills = { ...skills, [skill]: rank + 1 };
      break;
    }
  }
  return { ...leader, level, skills };
}

export function leaderEffects(data: GameData, leader: Pick<LeaderState, 'skills'>): LeaderEffects {
  const sum: Record<string, number> = {};
  for (const [skill, rank] of Object.entries(leader.skills)) {
    for (const [key, value] of Object.entries(data.leaders.skills[skill]?.effectsPerRank ?? {})) sum[key] = (sum[key] ?? 0) + value * rank;
  }
  return { attack: sum.attack ?? 0, defense: sum.defense ?? 0, nerve: sum.nerve ?? 0, loot: sum.loot ?? 0 };
}

// The horde's units under its leader; against the village it holds a
// grudge against, harder still.
export function ledStats(
  data: GameData,
  base: (unit: string) => UnitStats,
  effects: LeaderEffects | null,
  grudge = false,
): (unit: string) => UnitStats {
  if (!effects) return base;
  const attack = 1 + effects.attack + (grudge ? data.leaders.grudge.attack : 0);
  const defense = 1 + effects.defense;
  return (unit) => {
    const stats = base(unit);
    return { ...stats, attack: stats.attack * attack, defense: stats.defense * defense };
  };
}

export interface LeaderOutcome {
  // The horde beat the defenders (raid or raze), and razed the village.
  readonly hordeWon: boolean;
  readonly razed?: boolean;
  readonly kills: number;
  // Not one of the horde left standing.
  readonly wiped: boolean;
  // Where they were beaten (a village, or null in the field).
  readonly villageId: number | null;
}

export interface LeaderAfter {
  readonly state: LeaderState;
  readonly dead: boolean;
  // Driven off: wounded for this long (ms, world speed applied).
  readonly woundMs: number;
  readonly grudgeVillageId: number | null | undefined;
}

// What a battle does to its horde's leader: experience always; a win
// counts more; beaten, they flee wounded and remember who beat them, unless
// their horde fell to the last, and they with it.
export function leaderAfterBattle(data: GameData, front: string, leader: LeaderState, outcome: LeaderOutcome, worldSpeed: number): LeaderAfter {
  const xp = data.leaders.xp;
  if (!outcome.hordeWon && outcome.wiped) return { state: leader, dead: true, woundMs: 0, grudgeVillageId: undefined };
  const gained =
    xp.battle +
    xp.perKill * outcome.kills +
    (outcome.hordeWon ? xp.win + (outcome.razed ? xp.raze : 0) : xp.escape);
  return {
    state: gainLeaderXp(data, front, leader, gained),
    dead: false,
    woundMs: outcome.hordeWon ? 0 : Math.round((data.leaders.woundHours * MS_PER_HOUR) / worldSpeed),
    grudgeVillageId: outcome.hordeWon ? undefined : outcome.villageId,
  };
}
