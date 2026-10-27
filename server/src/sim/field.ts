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
  if (setup.choke && input.holdersStance === 'hold_the_line') holderDefense += data.field.choke.holdTheLineDefense;
  return {
    holderAttack: setup.ambush && first ? 1 + data.field.ambush.bonus + (input.ambushBonus ?? 0) : 1,
    holderDefense,
    hordeAttack: (setup.choke ? data.field.choke.attackerFactor : 1) * (setup.river ? data.field.river.attackerFactor : 1),
    hordeStanceless: setup.ambush && first,
  };
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
