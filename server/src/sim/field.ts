// Field battles (PLAN.md §6.3): what a hex gives the army holding it.
import type { GameData, TerrainId } from '../data/index.js';
import { hexKey, neighbors, type Hex } from './hex.js';
import { edgeKey } from './land.js';

export interface Setup {
  // Surprise on the first round (army in place early, on cover).
  readonly ambush: boolean;
  // Narrow ground: attackers can't bring their numbers to bear.
  readonly choke: boolean;
  // A fort on the hex.
  readonly fort: boolean;
  // The horde came over a river (by a bridge) into the hex.
  readonly river?: boolean;
  // The defense the holders' wagon fort gives (absent: none).
  readonly wagonFort?: number;
}

export function isChokePoint(data: GameData, terrain: ReadonlyMap<string, TerrainId>, cell: Hex): boolean {
  const passable = (h: Hex) => {
    const t = terrain.get(hexKey(h));
    return t !== undefined && data.terrain.terrain[t].moveCost !== null;
  };
  if (!passable(cell)) return false;
  return neighbors(cell).filter((n) => !passable(n)).length >= data.field.choke.minBlockedNeighbors;
}

export function setupAt(
  data: GameData,
  input: {
    terrain: ReadonlyMap<string, TerrainId>;
    cell: Hex;
    // When the first army holding the hex got there, and when the horde does.
    readySince: Date;
    hordeArrives: Date;
    worldSpeed: number;
    fort: boolean;
    river?: boolean;
  },
): Setup {
  const type = input.terrain.get(hexKey(input.cell));
  const prepMs = (data.field.ambush.prepMinutes * 60_000) / input.worldSpeed;
  return {
    ambush: type !== undefined && data.field.ambush.terrain.includes(type) && input.hordeArrives.getTime() - input.readySince.getTime() >= prepMs,
    choke: isChokePoint(data, input.terrain, input.cell),
    fort: input.fort,
    river: input.river ?? false,
  };
}

// Multipliers for one round: the holders' attack and defense, the horde's
// attack, and whether the horde fights without its stance.
export function setupFactors(
  data: GameData,
  setup: Setup,
  input: { round: number; holdersStance: string; ambushBonus?: number },
): { holderAttack: number; holderDefense: number; hordeAttack: number; hordeStanceless: boolean } {
  const first = input.round === 1;
  let holderDefense = 1;
  if (setup.fort) holderDefense += data.field.fort.defenseBonus;
  holderDefense += setup.wagonFort ?? 0;
  if (setup.choke && input.holdersStance === 'hold_the_line') holderDefense += data.field.choke.holdTheLineDefense;
  return {
    holderAttack: setup.ambush && first ? 1 + data.field.ambush.bonus + (input.ambushBonus ?? 0) : 1,
    holderDefense,
    hordeAttack: (setup.choke ? data.field.choke.attackerFactor : 1) * (setup.river ? data.field.river.attackerFactor : 1),
    hordeStanceless: setup.ambush && first,
  };
}

// Whether a unit is a wagon (a Military Caravan), not a soldier.
export function isWagon(data: GameData, unit: string): boolean {
  return data.units.units[unit]?.wagon === true;
}

export function wagonsIn(data: GameData, units: Readonly<Record<string, number>>): number {
  let n = 0;
  for (const [unit, count] of Object.entries(units)) if (isWagon(data, unit)) n += count;
  return n;
}

// The defense a wagon fort gives the armies holding a hex (field.json
// wagonFort): the wagons of those whose ring stands ready by `at`, for
// each `menPerWagon` soldiers of them all, at most `maxBonus`.
export function wagonFortBonus(
  data: GameData,
  holders: readonly { units: Readonly<Record<string, number>>; wagonFortAt: Date | null }[],
  at: Date,
): number {
  const rules = data.field.wagonFort;
  let wagons = 0;
  let soldiers = 0;
  for (const army of holders) {
    const n = wagonsIn(data, army.units);
    if (army.wagonFortAt && army.wagonFortAt.getTime() <= at.getTime()) wagons += n;
    for (const count of Object.values(army.units)) soldiers += count;
    soldiers -= n;
  }
  if (wagons === 0) return 0;
  return Math.min(rules.maxBonus, (rules.bonusPerWagon * wagons) / Math.max(1, Math.ceil(soldiers / rules.menPerWagon)));
}

// The step of a route that enters `cell`, if it passes there.
export function stepInto(path: readonly { q: number; r: number; atMs: number }[], cell: Hex, fromMs = 0) {
  return path.find((s) => s.q === cell.q && s.r === cell.r && s.atMs >= fromMs) ?? null;
}

// Whether a route came into `cell` over a river: the edge from the step
// before it is one of `rivers` (edgeKey). Only bridged edges can be crossed.
export function cameOverRiver(path: readonly { q: number; r: number }[], cell: Hex, rivers: ReadonlySet<string>): boolean {
  const i = path.findIndex((s) => s.q === cell.q && s.r === cell.r);
  return i > 0 && rivers.has(edgeKey(path[i - 1]!, cell));
}

// The grain a fort or supply point keeps at most.
export function grainCapacity(data: GameData, kind: 'fort' | 'supply'): number {
  return kind === 'supply' ? data.field.supplyPoint.grainCapacity : data.field.fort.grainCapacity;
}
