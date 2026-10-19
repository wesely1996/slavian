// Clans (PLAN.md §9): each player's clan adds its effects to their
// bonuses, marked `clan.<id>` so the clan's own unit and building can be
// told apart. Unique buildings add their effects per level to their village.
import type { GameData } from '../data/index.js';
import type { Front } from './mapgen.js';
import { bonus, type Bonuses } from './research.js';

export function clanBonuses(data: GameData, clan: string | null): Record<string, number> {
  const def = clan ? data.clans.clans[clan] : undefined;
  if (!def) return {};
  return { ...def.effects, [`clan.${clan}`]: 1 };
}

export function hasClan(bonuses: Bonuses, clan: string): boolean {
  return bonus(bonuses, `clan.${clan}`) > 0;
}

// The clan's name, for "Only Rod Rysa can train a Forest Archer".
export function clanName(data: GameData, clan: string): string {
  return data.clans.clans[clan]?.name ?? clan;
}

// The owner's bonuses plus what the village's buildings add.
export function villageBonuses(
  data: GameData,
  state: { readonly plots: Readonly<Record<string, { building: string | null; level: number }>>; readonly bonuses: Bonuses },
): Bonuses {
  let out: Record<string, number> | null = null;
  for (const plot of Object.values(state.plots)) {
    const effects = plot.building && plot.level > 0 ? data.buildings.buildings[plot.building]?.effects : undefined;
    if (!effects) continue;
    out ??= { ...state.bonuses };
    for (const [key, value] of Object.entries(effects)) out[key] = (out[key] ?? 0) + value * plot.level;
  }
  return out ?? state.bonuses;
}

// Against the North front, cold-hardy clans defend better.
export function againstFront(bonuses: Bonuses, front: Front): Bonuses {
  const cold = front === 'north' ? bonus(bonuses, 'coldDefense') : 0;
  return cold ? { ...bonuses, 'defense.all': bonus(bonuses, 'defense.all') + cold } : bonuses;
}
