// Raids beyond the map's edge (data/raids.json): an army marches to the
// edge on a front's side, fights `depth` field battles in the enemy's lands
// and then besieges the front's stronghold, carrying home what it takes.
import type { GameData, Stance, TerrainId } from '../data/index.js';
import { battleOutcome, battleRng, enemyStats, resolveRound, subtractUnits, total, type Champion, type UnitStats } from './battle.js';
import { hex, hexDistance, hexKey, ring, type Hex } from './hex.js';
import { frontOf, type Front } from './mapgen.js';
import { mapResources, type Resources } from './resources.js';
import { createRng } from './rng.js';
import { composeWave } from './waves.js';
import type { Units } from './training.js';

export interface RaidField {
  name: string;
  army: { attack: number; defense: number };
  enemy: { attack: number; defense: number };
}

// One stage of a raid: a field battle, or (the last) the stronghold's siege.
export interface RaidStage {
  stage: number;
  name: string;
  stronghold: boolean;
  field: RaidField | null;
  enemy: Units;
}

export type RaidFind = { type: 'gear' } | { type: 'scroll' } | { type: 'ember' };

// The hex on the map's last ring, on the front's side, nearest `from` that
// an army can stand on (null: none).
export function raidEdge(data: GameData, terrain: ReadonlyMap<string, TerrainId>, radius: number, front: Front, from: Hex): Hex | null {
  const cells = ring(hex(0, 0), radius).filter((cell) => {
    const type = terrain.get(hexKey(cell));
    return type !== undefined && type !== 'holy_city' && data.terrain.terrain[type].moveCost !== null && frontOf(cell) === front;
  });
  cells.sort((a, b) => hexDistance(a, from) - hexDistance(b, from) || a.q - b.q || a.r - b.r);
  return cells[0] ?? null;
}

// The fields a raid fights through, in a seeded order, then its stronghold.
export function raidStage(data: GameData, input: { front: Front; depth: number; stage: number; waves: number; seed: number; id: number; players: number }): RaidStage {
  const rules = data.raids;
  const front = rules.fronts[input.front]!;
  const order = front.fields.map((_, i) => i);
  const rng = createRng((input.seed ^ Math.imul(input.id + 1, 0x5bd1e995) ^ 0x4a1d) >>> 0);
  for (let i = order.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [order[i], order[j]] = [order[j]!, order[i]!];
  }
  const stronghold = input.stage > input.depth;
  const size =
    rules.enemy.baseUnits * rules.enemy.growthPerStage ** (input.stage - 1) * rules.enemy.growthPerWave ** input.waves * (stronghold ? rules.stronghold.sizeFactor : 1);
  const enemy = composeWave(data, input.front, input.waves + input.stage, Math.max(1, Math.round(size)), (input.seed ^ Math.imul(input.id + 7, 0x27d4eb2f) ^ input.stage) >>> 0, input.players);
  const field = stronghold ? null : front.fields[order[(input.stage - 1) % order.length]!]!;
  return { stage: input.stage, name: stronghold ? front.stronghold : field!.name, stronghold, field, enemy };
}

// The share of a scheduled horde gathered at its encampment `hoursEarly`
// game hours before it sets out (raids.json strike).
export function strikeShare(data: GameData, hoursEarly: number): number {
  const rules = data.raids.strike;
  return 1 - (1 - rules.minShare) * Math.min(1, Math.max(0, hoursEarly) / rules.gatherHours);
}

// The encampment's battle: `share` of the horde's troops (at least one),
// behind its walls like a stronghold.
export function strikeStage(data: GameData, composition: Units, share: number): RaidStage {
  const enemy: Record<string, number> = {};
  for (const unit of Object.keys(composition).sort()) {
    const n = Math.round((composition[unit] ?? 0) * share);
    if (n > 0) enemy[unit] = n;
  }
  if (total(enemy) === 0) {
    const first = Object.keys(composition).sort().find((u) => (composition[u] ?? 0) > 0);
    if (first) enemy[first] = 1;
  }
  return { stage: 1, name: data.raids.strike.name, stronghold: true, field: null, enemy };
}

// A raid battle: the army attacks, round by round, until one side breaks or
// the last round passes (the army falls back). On a field the terrain
// scales both sides; the stronghold's defenders fight from behind its walls.
export function raidBattle(
  data: GameData,
  input: {
    army: Units;
    armyStats: (unit: string) => UnitStats;
    armyStance: Stance;
    stage: RaidStage;
    front: Front;
    seed: number;
    id: number;
    // Its hero and general fighting in its ranks, and its stats once the
    // hero has fallen (the general in command).
    champions?: readonly Champion[];
    statsWithoutHero?: (unit: string) => UnitStats;
  },
): { won: boolean; rounds: { round: number; attackerLosses: Units; defenderLosses: Units; attackerLeft: number; defenderLeft: number }[]; armyNow: Units; enemyNow: Units; fallen: string[] } {
  const rules = data.raids;
  const field = input.stage.field;
  // Battering rams take the stronghold's walls off its defenders, a share each.
  let breach = 0;
  for (const [unit, n] of Object.entries(input.army)) breach += (data.units.units[unit]?.breach ?? 0) * n;
  const walls = input.stage.stronghold ? 1 + rules.stronghold.walls * Math.max(0, 1 - breach) : 1;
  const base = enemyStats(data, input.front);
  const enemyStatsAt = (unit: string): UnitStats => {
    const s = base(unit);
    return { ...s, attack: s.attack * (field?.enemy.attack ?? 1), defense: s.defense * (field?.enemy.defense ?? 1) * walls };
  };
  let champions = [...(input.champions ?? [])];
  const fallen: string[] = [];
  const armyStatsAt = (unit: string): UnitStats => {
    const s = (fallen.includes('hero') && input.statsWithoutHero ? input.statsWithoutHero : input.armyStats)(unit);
    return { ...s, attack: s.attack * (field?.army.attack ?? 1), defense: s.defense * (field?.army.defense ?? 1) };
  };
  const enemyStance = input.stage.stronghold ? rules.stronghold.stance : rules.fieldStance;
  let armyNow = { ...input.army };
  let enemyNow = { ...input.stage.enemy };
  const rounds = [];
  for (let round = 1; round <= data.battle.maxRounds; round++) {
    const result = resolveRound(
      data,
      { units: armyNow, stance: input.armyStance, stats: armyStatsAt, home: false, champions },
      { units: enemyNow, stance: enemyStance, stats: enemyStatsAt, home: input.stage.stronghold },
      battleRng(input.seed, input.id + 0x30000, round),
    );
    for (const id of result.attackerFallen[0] ?? []) fallen.push(id);
    champions = champions.filter((c) => !fallen.includes(c.id));
    armyNow = subtractUnits(armyNow, result.attackerLosses);
    enemyNow = subtractUnits(enemyNow, result.defenderLosses);
    rounds.push({ round, attackerLosses: result.attackerLosses, defenderLosses: result.defenderLosses, attackerLeft: total(armyNow), defenderLeft: total(enemyNow) });
    const outcome = battleOutcome(data, {
      round,
      attackerStance: input.armyStance,
      attackerInitial: input.army,
      attackerNow: armyNow,
      defenderStance: enemyStance,
      defenderInitial: input.stage.enemy,
      defenderNow: enemyNow,
    });
    if (outcome !== 'ongoing') return { won: outcome === 'raided', rounds, armyNow, enemyNow, fallen };
  }
  return { won: false, rounds, armyNow, enemyNow, fallen };
}

// How much an army can carry home: each fighting unit, and each military
// caravan's wagon.
export function raidCapacity(data: GameData, units: Units): number {
  let carry = 0;
  for (const [unit, n] of Object.entries(units)) {
    const def = data.units.units[unit];
    if (!def || n <= 0) continue;
    if (def.supplyGrain) carry += data.raids.carry.perWagon * n;
    else if (def.family !== 'scout' && unit !== 'settler') carry += data.raids.carry.perSoldier * n;
  }
  return carry;
}

// What a battle won yields: per enemy killed, and the stronghold's stores
// when it is sacked (the North gives little of it).
export function raidLoot(data: GameData, front: Front, kills: number, stronghold: boolean): Resources {
  const rules = data.raids;
  const factor = data.enemies.fronts[front]!.personality.lootFactor * (front === 'north' ? rules.north.resourceShare : 1);
  return mapResources((kind) => Math.round((rules.loot.perKill[kind] * kills + (stronghold ? rules.loot.stronghold[kind] : 0)) * factor));
}

// Adds `gain` to `carried`, as far as `capacity` allows (each kind in turn).
export function carryHome(carried: Resources, gain: Resources, capacity: number): Resources {
  let room = Math.max(0, capacity - total(carried));
  return mapResources((kind) => {
    const take = Math.min(room, gain[kind]);
    room -= take;
    return carried[kind] + take;
  });
}

// What the North yields besides, after a battle won: each kind of find by
// its chance (the stronghold's the higher), seeded by the raid and stage.
export function northFinds(data: GameData, input: { stronghold: boolean; seed: number; id: number; stage: number }): RaidFind[] {
  const rules = data.raids.north;
  const rng = createRng((input.seed ^ Math.imul(input.id + 3, 0x1b873593) ^ Math.imul(input.stage + 1, 0x85ebca6b)) >>> 0);
  const factor = input.stronghold ? rules.strongholdFactor : 1;
  const out: RaidFind[] = [];
  for (const type of ['gear', 'scroll', 'ember'] as const) if (rng() < Math.min(1, rules.finds[type] * factor)) out.push({ type });
  return out;
}
