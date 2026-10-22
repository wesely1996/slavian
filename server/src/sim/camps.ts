// Bandit camps and monster lairs (PLAN.md §7.5): where they spawn, how they
// grow and feed the next wave, armies clearing them, and caravan ambushes.
// Numbers in data/camps.json.
import type { GameData, TerrainId } from '../data/index.js';
import { battleOutcome, battleRng, enemyStats, resolveRound, subtractUnits, total, type UnitStats } from './battle.js';
import { hexDistance, hexKey, spiral, type Hex } from './hex.js';
import type { Front } from './mapgen.js';
import { mapResources, type Resources } from './resources.js';
import type { PathStep } from './waves.js';

export type Units = Record<string, number>;

export function campSize(data: GameData, waveIndex: number): number {
  const { baseUnits, growthPerWave } = data.camps.spawn;
  return Math.max(1, Math.round(baseUnits * growthPerWave ** waveIndex));
}

// Free hexes near a horde's road, away from villages, in a seeded order.
export function spawnSites(
  data: GameData,
  input: {
    terrain: ReadonlyMap<string, TerrainId>;
    path: readonly PathStep[];
    villages: readonly Hex[];
    taken: ReadonlySet<string>;
    rng: () => number;
    count: number;
  },
): Hex[] {
  const { nearRoad, minVillageDistance } = data.camps.spawn;
  const seen = new Set<string>();
  const candidates: Hex[] = [];
  for (const step of input.path) {
    for (const cell of spiral({ q: step.q, r: step.r }, nearRoad)) {
      const key = hexKey(cell);
      if (seen.has(key)) continue;
      seen.add(key);
      const type = input.terrain.get(key);
      if (type === undefined || type === 'holy_city' || data.terrain.terrain[type].moveCost === null) continue;
      if (data.terrain.terrain[type].edge || input.taken.has(key)) continue;
      if (input.villages.some((v) => hexDistance(v, cell) < minVillageDistance)) continue;
      candidates.push(cell);
    }
  }
  const picked: Hex[] = [];
  while (picked.length < input.count && candidates.length) {
    const [cell] = candidates.splice(Math.floor(input.rng() * candidates.length), 1);
    if (picked.every((p) => hexDistance(p, cell!) > 1)) picked.push(cell!);
  }
  return picked;
}

// Where a village's starter camp goes: a free, passable hex within
// starter.minDistance-maxDistance of it, no nearer any other village or the
// Holy City, in a
// seeded order (null if none).
export function starterSite(
  data: GameData,
  input: {
    terrain: ReadonlyMap<string, TerrainId>;
    village: Hex;
    villages: readonly Hex[];
    taken: ReadonlySet<string>;
    rng: () => number;
  },
): Hex | null {
  const { minDistance, maxDistance } = data.camps.starter;
  const candidates = spiral(input.village, maxDistance).filter((cell) => {
    const key = hexKey(cell);
    const type = input.terrain.get(key);
    if (type === undefined || type === 'holy_city' || data.terrain.terrain[type].moveCost === null) return false;
    if (data.terrain.terrain[type].edge || input.taken.has(key)) return false;
    const distance = hexDistance(input.village, cell);
    // Not at the Holy City's gates either.
    return distance >= minDistance && hexDistance(cell, { q: 0, r: 0 }) >= minDistance && input.villages.every((v) => hexDistance(v, cell) >= minDistance);
  });
  if (candidates.length === 0) return null;
  return candidates[Math.floor(input.rng() * candidates.length)]!;
}

// A camp draws in more of its kind, up to a limit.
export function grow(data: GameData, units: Units): Units {
  const { share, maxUnits } = data.camps.growth;
  const now = total(units);
  if (now === 0 || now >= maxUnits) return units;
  const extra = Math.min(maxUnits - now, Math.max(1, Math.round(now * share)));
  const next: Units = { ...units };
  const kinds = Object.entries(units).filter(([, n]) => n > 0).sort((a, b) => b[1] - a[1]);
  for (let i = 0; i < extra; i++) {
    const [unit] = kinds[i % kinds.length]!;
    next[unit] = (next[unit] ?? 0) + 1;
  }
  return next;
}

// A wave of the camp's front sets out: part of the camp goes with it.
export function feed(data: GameData, units: Units): { sent: Units; kept: Units } {
  const sent: Units = {};
  for (const [unit, n] of Object.entries(units)) {
    const s = Math.floor(n * data.camps.feed.share);
    if (s > 0) sent[unit] = s;
  }
  return { sent, kept: subtractUnits(units, sent) };
}

export function addUnits(a: Units, b: Units): Units {
  const sum: Units = { ...a };
  for (const [unit, n] of Object.entries(b)) sum[unit] = (sum[unit] ?? 0) + n;
  return sum;
}

function strength(units: Units, stats: (unit: string) => UnitStats): number {
  return Object.entries(units).reduce((sum, [unit, n]) => sum + n * stats(unit).attack, 0);
}

export interface AssaultRound {
  round: number;
  attackerLosses: Units;
  defenderLosses: Units;
  attackerLeft: number;
  defenderLeft: number;
}

// An army storms a camp: rounds until one side breaks or the last round
// passes (the army falls back). The camp fights from behind its palisade.
export function assault(
  data: GameData,
  input: {
    army: Units;
    armyStats: (unit: string) => UnitStats;
    armyStance: Parameters<typeof battleOutcome>[1]['attackerStance'];
    camp: Units;
    front: Front;
    seed: number;
    id: number;
  },
): { cleared: boolean; rounds: AssaultRound[]; armyNow: Units; campNow: Units } {
  const campStats = enemyStats(data, input.front);
  const stance = data.camps.assault.stance;
  let armyNow = { ...input.army };
  let campNow = { ...input.camp };
  const rounds: AssaultRound[] = [];
  for (let round = 1; round <= data.battle.maxRounds; round++) {
    const result = resolveRound(
      data,
      { units: armyNow, stance: input.armyStance, stats: input.armyStats, home: false },
      { units: campNow, stance, stats: campStats, home: true },
      battleRng(input.seed, input.id + 0x10000, round),
    );
    armyNow = subtractUnits(armyNow, result.attackerLosses);
    campNow = subtractUnits(campNow, result.defenderLosses);
    rounds.push({ round, attackerLosses: result.attackerLosses, defenderLosses: result.defenderLosses, attackerLeft: total(armyNow), defenderLeft: total(campNow) });
    const outcome = battleOutcome(data, {
      round,
      attackerStance: input.armyStance,
      attackerInitial: input.army,
      attackerNow: armyNow,
      defenderStance: stance,
      defenderInitial: input.camp,
      defenderNow: campNow,
    });
    // 'raided': the defenders (the camp) broke; 'defended': the army did.
    if (outcome !== 'ongoing') return { cleared: outcome === 'raided', rounds, armyNow, campNow };
  }
  return { cleared: false, rounds, armyNow, campNow };
}

export function campLoot(data: GameData, units: Units): Resources {
  const n = total(units);
  return mapResources((kind) => Math.round(data.camps.loot.perUnit[kind] * n));
}

// A caravan passes a camp: its escort beats them off, or it loses part of
// its load (and the escort some of its troops).
export function ambush(
  data: GameData,
  input: { escort: Units; escortStats: (unit: string) => UnitStats; camp: Units; front: Front; cargo: Resources },
): { beatenOff: boolean; lost: Resources; escortLosses: Units } {
  const rules = data.camps.ambush;
  const escort = strength(input.escort, input.escortStats);
  const camp = strength(input.camp, enemyStats(data, input.front));
  if (escort > 0 && escort >= camp * rules.escortRatio) return { beatenOff: true, lost: mapResources(() => 0), escortLosses: {} };
  const escortLosses: Units = {};
  for (const [unit, n] of Object.entries(input.escort)) {
    const dead = Math.ceil(n * rules.escortLoss);
    if (dead > 0) escortLosses[unit] = dead;
  }
  return { beatenOff: false, lost: mapResources((kind) => Math.floor(input.cargo[kind] * rules.cargoShare)), escortLosses };
}

// The first step of a road within reach of a camp, if it passes one.
export function passesCamp(data: GameData, path: readonly PathStep[], camp: Hex): PathStep | null {
  return path.find((s) => hexDistance({ q: s.q, r: s.r }, camp) <= data.camps.ambush.reach) ?? null;
}
