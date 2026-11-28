// Raids beyond the map's edge (data/raids.json): an army marches to the
// edge on a front's side, fights `depth` field battles in the enemy's lands
// and then besieges the front's stronghold, carrying home what it takes.
import type { GameData, Stance, TerrainId } from '../data/index.js';
import { linesFor, linesLog, type LineSetup, type LineState, type Move, type SideId } from './lines.js';
import { battleOutcome, battleRng, enemyStats, NO_AFFLICTIONS, resolveRound, subtractUnits, total, type Champion, type UnitStats } from './battle.js';
import { findPath, hex, hexDistance, hexKey, ring, type Hex } from './hex.js';
import { bandOf as enemyBand, enemyLands } from './enemyLands.js';
import { fastestStep, moveCostOn, type Land } from './land.js';
import { frontOf, type Front } from './mapgen.js';
import { mapResources, type Resources } from './resources.js';
import { createRng } from './rng.js';
import { composeWave, type PathStep } from './waves.js';
import type { Units } from './training.js';

const MS_PER_HOUR = 3_600_000;

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
    // Fought in lines (battle.json lines); nobody maneuvers at a stronghold's walls.
    lines?: LineSetup;
    // The season's toughness for everyone (sim/seasons.ts seasonDefense).
    season?: number;
  },
): { won: boolean; rounds: { round: number; maneuver?: { by: SideId; kind: Move }; breakthrough?: { by: SideId; kind: Move }; attackerLosses: Units; defenderLosses: Units; attackerLeft: number; defenderLeft: number }[]; armyNow: Units; enemyNow: Units; fallen: string[] } {
  const rules = data.raids;
  const field = input.stage.field;
  // Battering rams take the stronghold's walls off its defenders, a share each.
  let breach = 0;
  for (const [unit, n] of Object.entries(input.army)) breach += (data.units.units[unit]?.breach ?? 0) * n;
  const walls = input.stage.stronghold ? 1 + rules.stronghold.walls * Math.max(0, 1 - breach) : 1;
  const base = enemyStats(data, input.front);
  // The deeper, the tougher.
  const tough = 1 + rules.enemy.toughnessPerStage * Math.max(0, input.stage.stage - 1);
  const enemyStatsAt = (unit: string): UnitStats => {
    const s = base(unit);
    return { ...s, attack: s.attack * (field?.enemy.attack ?? 1) * tough, defense: s.defense * (field?.enemy.defense ?? 1) * walls * tough };
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
  // Burning and poison carry from round to round.
  let afflictions = NO_AFFLICTIONS;
  let lineState: LineState | undefined;
  const lines = input.lines ? { ...input.lines, still: input.stage.stronghold } : undefined;
  for (let round = 1; round <= data.battle.maxRounds; round++) {
    const result = resolveRound(
      data,
      { units: armyNow, stance: input.armyStance, stats: armyStatsAt, home: false, champions },
      { units: enemyNow, stance: enemyStance, stats: enemyStatsAt, home: input.stage.stronghold },
      battleRng(input.seed, input.id + 0x30000, round),
      afflictions,
      undefined,
      lines ? linesFor(lines, round, lineState) : undefined,
      input.season ?? 1,
    );
    afflictions = result.afflictions;
    lineState = result.lines?.state;
    for (const id of result.attackerFallen[0] ?? []) fallen.push(id);
    champions = champions.filter((c) => !fallen.includes(c.id));
    armyNow = subtractUnits(armyNow, result.attackerLosses);
    enemyNow = subtractUnits(enemyNow, result.defenderLosses);
    rounds.push({ ...linesLog(result.lines), round, attackerLosses: result.attackerLosses, defenderLosses: result.defenderLosses, attackerLeft: total(armyNow), defenderLeft: total(enemyNow) });
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

// How much an army can carry home: each unit's own carry (units.json),
// wagons the most.
export function raidCapacity(data: GameData, units: Units): number {
  let carry = 0;
  for (const [unit, n] of Object.entries(units)) {
    const def = data.units.units[unit];
    if (def && n > 0) carry += def.carry * n;
  }
  return carry;
}

// What a battle won yields: per enemy killed, and the stronghold's stores
// when it is sacked (the North gives little of it); more the deeper the
// battle (`stage`) and the more the front hates (`hatred`).
export function raidLoot(data: GameData, front: Front, kills: number, stronghold: boolean, stage = 1, hatred = 0): Resources {
  const rules = data.raids;
  const factor =
    data.enemies.fronts[front]!.personality.lootFactor *
    (front === 'north' ? rules.north.resourceShare : 1) *
    (1 + rules.loot.perStage * Math.max(0, stage - 1)) *
    (1 + rules.loot.perHatred * Math.max(0, hatred));
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

// How much longer a step into fog takes for an army with `scouts`: up to
// road.fogFactor, each scout cutting scoutCut of the extra.
export function fogFactor(data: GameData, scouts: number): number {
  const road = data.raids.road;
  return 1 + (road.fogFactor - 1) * Math.max(0, 1 - road.scoutCut * scouts);
}

// The road a raid marches into the front's lands from the edge hex
// `from`: straight deeper (to the nearest hex of band `toBand` it can
// reach), on `land` at `hexesPerHour`, steps into bands beyond `sight`
// taking fogFactor as long. Null when none leads there.
export function raidRoad(
  data: GameData,
  input: {
    land: Land;
    world: { seed: number; radius: number | null; activeFronts: readonly string[] };
    from: Hex;
    front: string;
    toBand: number;
    sight: number;
    scouts: number;
    hexesPerHour: number;
    worldSpeed: number;
  },
): PathStep[] | null {
  const { world } = input;
  if (world.radius === null) return null;
  const lands = enemyLands(data, world.seed, world.radius, world.activeFronts as Front[]);
  const bandAt = new Map(lands.map((e) => [hexKey(e.cell), e.band]));
  const moveCost = moveCostOn(data, input.land);
  const fog = fogFactor(data, input.scouts);
  const cost = (p: Hex, q: Hex): number | null => {
    const c = moveCost(p, q);
    if (c === null) return null;
    return (bandAt.get(hexKey(q)) ?? 0) > input.sight ? c * fog : c;
  };
  const goals = lands
    .map((e, i) => ({ e, i }))
    .filter(({ e }) => e.front === input.front && e.band === input.toBand && data.terrain.terrain[e.terrain].moveCost !== null)
    .sort((x, y) => hexDistance(x.e.cell, input.from) - hexDistance(y.e.cell, input.from) || x.i - y.i)
    .slice(0, 8);
  for (const { e } of goals) {
    const path = findPath(input.from, e.cell, cost, fastestStep(data, input.land));
    if (!path) continue;
    const msPerCost = MS_PER_HOUR / input.hexesPerHour / input.worldSpeed;
    let atMs = 0;
    return path.map((cell, i) => {
      if (i > 0) atMs += cost(path[i - 1]!, cell)! * msPerCost;
      return { q: cell.q, r: cell.r, atMs: Math.max(i, Math.round(atMs)) };
    });
  }
  return null;
}

// When each stage comes along the road (ms after it set out from the edge):
// field battle i as it enters band i, the stronghold at the road's end.
export function raidStageTimes(data: GameData, world: { seed: number; radius: number | null; activeFronts: readonly string[] }, road: readonly PathStep[], depth: number): number[] {
  const bandOf = (s: PathStep) => (world.radius === null ? 0 : (enemyBand(data, hex(s.q, s.r), world.radius) ?? 0));
  const times: number[] = [];
  for (let stage = 1; stage <= depth; stage++) {
    const step = road.find((s) => bandOf(s) >= stage) ?? road.at(-1)!;
    times.push(step.atMs);
  }
  times.push(road.at(-1)!.atMs);
  return times;
}
