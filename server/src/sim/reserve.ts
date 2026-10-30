// The military reserve (data/armies.json `reserve`): grain kept for armies
// in the military buildings, apart from the granary. An army leaving a
// settlement takes its grain from the reserve alone; troops in a village
// eat from the granary. Grain an army brings in goes into it first. It tops
// itself up from the granary when a building finishes a level, a training
// batch is done, and an army comes in.
import type { GameData } from '../data/index.js';
import { receive } from './logistics.js';
import { amountsAt, spend } from './resources.js';
import type { Plots, VillageState } from './village.js';

// Grain the reserve keeps at most: `grainPerLevel` for each level of each
// military building.
export function reserveCapacity(data: GameData, plots: Plots): number {
  let levels = 0;
  for (const plot of Object.values(plots)) {
    if (plot.building && data.armies.reserve.buildings.includes(plot.building)) levels += plot.level;
  }
  return levels * data.armies.reserve.grainPerLevel;
}

export function reserveOf(state: VillageState): number {
  return state.reserve ?? 0;
}

function grainOnly(grain: number) {
  return { wood: 0, stone: 0, grain, iron: 0 };
}

// Fills the reserve from the granary; over its capacity (a building lost),
// the rest goes back into the granary.
export function topUpReserve(data: GameData, state: VillageState, at: Date): VillageState {
  const cap = reserveCapacity(data, state.plots);
  const reserve = reserveOf(state);
  if (reserve > cap) {
    return { ...state, reserve: cap, ledger: receive(state.ledger, at, grainOnly(reserve - cap)).ledger };
  }
  const moved = Math.min(cap - reserve, amountsAt(state.ledger, at).grain);
  if (moved <= 0) return state;
  return { ...state, reserve: reserve + moved, ledger: spend(state.ledger, at, grainOnly(moved)) };
}

// Grain an army leaving takes, from the reserve alone (no more than
// reserveOf): the granary is not touched.
export function takeForArmy(state: VillageState, grain: number): VillageState {
  return grain <= 0 ? state : { ...state, reserve: Math.max(0, reserveOf(state) - grain) };
}

// Grain an army brings in: into the reserve first, the rest into the
// granary (as far as it holds it).
export function storeFromArmy(data: GameData, state: VillageState, grain: number, at: Date): VillageState {
  if (grain <= 0) return state;
  const room = Math.max(0, reserveCapacity(data, state.plots) - reserveOf(state));
  const toReserve = Math.min(grain, room);
  return {
    ...state,
    reserve: reserveOf(state) + toReserve,
    ledger: grain - toReserve > 0 ? receive(state.ledger, at, grainOnly(grain - toReserve)).ledger : state.ledger,
  };
}
