// Player against player (armies.json pvp): in a PvP world a player may
// attack another player's village. The fight is resolved at once when the
// army arrives: the attacking army against the village's garrison and the
// armies standing in it, round after round until one side breaks or the
// last round passes (then the defenders hold).
import type { GameData, Stance } from '../data/index.js';
import { RuleError } from '../errors.js';
import {
  battleOutcome,
  battleRng,
  NO_AFFLICTIONS,
  resolveRound,
  subtractUnits,
  total,
  type Champion,
  type UnitStats,
} from './battle.js';
import type { Units } from './training.js';

// When a village founded at `foundedAt` stops being safe from other
// players (null: never was, or not a PvP world).
export function protectedUntil(data: GameData, world: { pvp: boolean; speed: number }, foundedAt: Date | null | undefined): Date | null {
  if (!world.pvp || !foundedAt) return null;
  return new Date(foundedAt.getTime() + (data.armies.pvp.protectionHours * 3_600_000) / world.speed);
}

// Whether `target` may be attacked by the owner of `home` now.
export function checkAttack(
  data: GameData,
  world: { pvp: boolean; speed: number },
  home: { ownerAccountId: number | null },
  target: { name: string; ownerAccountId: number | null; ruin?: unknown; foundedAt?: Date | null },
  at: Date,
): void {
  if (!world.pvp) throw new RuleError("Players don't attack each other in this world");
  if (target.ownerAccountId === null || target.ownerAccountId === home.ownerAccountId) throw new RuleError("Attack another player's village");
  if (target.ruin) throw new RuleError(`${target.name} lies in ruins`);
  const until = protectedUntil(data, world, target.foundedAt);
  if (until && at < until) {
    const hours = Math.ceil(((until.getTime() - at.getTime()) / 3_600_000) * world.speed);
    throw new RuleError(`${target.name} is under protection for ${hours} more game hours`);
  }
}

export interface PvpForce {
  readonly units: Units;
  readonly stance: Stance;
  readonly stats: (unit: string) => UnitStats;
  readonly champions: readonly Champion[];
}

export interface PvpRound {
  round: number;
  attackerLosses: Record<string, number>;
  defenderLosses: Record<string, number>;
  attackerLeft: number;
  defenderLeft: number;
}

// The fight: `attacker` (with `statsWithoutHero` once its hero falls)
// against the garrison and the armies standing in the village, each in its
// own stance and breaking on its own; `defenders[0]` is the garrison.
export function pvpAssault(
  data: GameData,
  input: {
    attacker: PvpForce;
    statsWithoutHero?: (unit: string) => UnitStats;
    defenders: readonly PvpForce[];
    seed: number;
    id: number;
  },
): {
  won: boolean;
  rounds: PvpRound[];
  attackerNow: Record<string, number>;
  defendersNow: Record<string, number>[];
  attackerFallen: string[];
  defenderFallen: string[][];
} {
  let attackerNow: Record<string, number> = { ...input.attacker.units };
  let defendersNow: Record<string, number>[] = input.defenders.map((d) => ({ ...d.units }));
  const attackerFallen: string[] = [];
  const defenderFallen: string[][] = input.defenders.map(() => []);
  const rounds: PvpRound[] = [];
  let afflictions = NO_AFFLICTIONS;
  let won = false;
  for (let round = 1; round <= data.battle.maxRounds; round++) {
    const heroDown = attackerFallen.includes('hero') && input.statsWithoutHero;
    const result = resolveRound(
      data,
      {
        units: attackerNow,
        stance: input.attacker.stance,
        stats: heroDown ? input.statsWithoutHero! : input.attacker.stats,
        home: false,
        champions: input.attacker.champions.filter((c) => !attackerFallen.includes(c.id)),
      },
      {
        units: defendersNow.reduce<Record<string, number>>((sum, d) => {
          for (const [unit, n] of Object.entries(d)) sum[unit] = (sum[unit] ?? 0) + n;
          return sum;
        }, {}),
        stance: input.defenders[0]!.stance,
        stats: input.defenders[0]!.stats,
        home: true,
        groups: input.defenders.map((d, i) => ({
          units: defendersNow[i]!,
          stance: d.stance,
          stats: d.stats,
          champions: d.champions.filter((c) => !defenderFallen[i]!.includes(c.id)),
        })),
      },
      battleRng(input.seed, input.id + 0x20000, round),
      afflictions,
    );
    afflictions = result.afflictions;
    for (const id of result.attackerFallen[0] ?? []) attackerFallen.push(id);
    for (const [i, ids] of result.defenderFallen.entries()) for (const id of ids) defenderFallen[i]?.push(id);
    attackerNow = subtractUnits(attackerNow, result.attackerLosses);
    const shares = result.defenderGroupLosses!;
    defendersNow = defendersNow.map((d, i) => subtractUnits(d, shares[i] ?? {}));
    rounds.push({
      round,
      attackerLosses: result.attackerLosses,
      defenderLosses: result.defenderLosses,
      attackerLeft: total(attackerNow),
      defenderLeft: defendersNow.reduce((n, d) => n + total(d), 0),
    });
    const outcome = battleOutcome(data, {
      round,
      attackerStance: input.attacker.stance,
      attackerInitial: input.attacker.units,
      attackerNow,
      defenderStance: input.defenders[0]!.stance,
      defenderInitial: input.defenders[0]!.units,
      defenderNow: defendersNow.reduce<Record<string, number>>((sum, d) => {
        for (const [unit, n] of Object.entries(d)) sum[unit] = (sum[unit] ?? 0) + n;
        return sum;
      }, {}),
      defenderGroups: input.defenders.map((d, i) => ({ stance: d.stance, initial: d.units, now: defendersNow[i]! })),
    });
    if (outcome === 'ongoing') continue;
    won = outcome === 'raided';
    break;
  }
  return { won, rounds, attackerNow, defendersNow, attackerFallen, defenderFallen };
}

// What a won attack carries off: `lootShare` of every store, as much as
// the army can carry (each unit's `carry`), shared by the stores' sizes.
export function pvpLoot(data: GameData, stores: Readonly<Record<string, number>>, carry: number): Record<string, number> {
  const share = data.armies.pvp.lootShare;
  const wanted: Record<string, number> = {};
  let sum = 0;
  for (const [kind, n] of Object.entries(stores)) {
    wanted[kind] = Math.floor(Math.max(0, n) * share);
    sum += wanted[kind]!;
  }
  const scale = sum > carry && sum > 0 ? carry / sum : 1;
  return Object.fromEntries(Object.entries(wanted).map(([kind, n]) => [kind, Math.floor(n * scale)]));
}
