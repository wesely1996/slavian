// Shrines (data/buildings.json `deities`): a village's Shrine is raised to
// one god, picked once; the god's effects, times the Shrine's level, add to
// its owner's bonuses in all their villages.
import type { GameData } from '../data/index.js';
import { RuleError } from '../errors.js';
import type { Plots, VillageState } from './village.js';

// The plot holding the village's Shrine (a building with gods), if any.
export function shrinePlot(data: GameData, plots: Plots): string | null {
  for (const [id, plot] of Object.entries(plots)) {
    if (plot.building && data.buildings.buildings[plot.building]?.deities) return id;
  }
  return null;
}

// What the gods of a player's Shrines give, all villages together.
export function shrineBonuses(data: GameData, villages: readonly { readonly plots: Plots }[]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const { plots } of villages) {
    const id = shrinePlot(data, plots);
    const plot = id ? plots[id]! : null;
    if (!plot || plot.level <= 0 || !plot.deity) continue;
    const god = data.buildings.buildings[plot.building!]!.deities![plot.deity];
    if (!god) continue;
    for (const [key, value] of Object.entries(god.effects)) out[key] = (out[key] ?? 0) + value * plot.level;
  }
  return out;
}

// The village's Shrine raised to `deity`: once, and only once it stands.
export function pickDeity(data: GameData, state: VillageState, deity: string): VillageState {
  const id = shrinePlot(data, state.plots);
  const plot = id ? state.plots[id]! : null;
  if (!id || !plot || plot.level <= 0) throw new RuleError('Build a Shrine first');
  const def = data.buildings.buildings[plot.building!]!;
  if (plot.deity) throw new RuleError(`This ${def.name} already belongs to ${def.deities![plot.deity]?.name ?? plot.deity}`);
  if (!def.deities![deity]) throw new RuleError('No such god');
  return { ...state, plots: { ...state.plots, [id]: { ...plot, deity } } };
}
