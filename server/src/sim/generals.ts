// Generals: lesser heroes recruited at a Hero's Hall (data/heroes.json,
// `generals`). They have levels but no skills, gear or quests; a general
// leads the army it marches with, or commands the garrison of the village
// it stands in, adding its level's effects to theirs. Only the hero is
// wounded: a general whose side loses is killed. The Hero's Hall also
// shortens the time the hero spends wounded in its village.
import type { GameData } from '../data/index.js';
import { RuleError } from '../errors.js';
import { mapResources, type Resources } from './resources.js';

export type GeneralStatus = 'recruiting' | 'home' | 'traveling' | 'with_army';

export interface GeneralState {
  readonly name: string;
  readonly level: number;
  readonly xp: number;
}

// Names go round the list by the general's id.
export function generalName(data: GameData, id: number): string {
  const names = data.heroes.generals.names;
  return names[(id - 1) % names.length]!;
}

export function generalXpToNext(data: GameData, level: number): number {
  const { base, growth } = data.heroes.generals.levelXp;
  return Math.round(base * growth ** (level - 1));
}

// Adds XP, levelling up as far as it reaches.
export function generalGainXp<G extends GeneralState>(data: GameData, general: G, xp: number): G {
  const max = data.heroes.generals.maxLevel;
  let level = general.level;
  let pool = general.xp + Math.max(0, Math.floor(xp));
  while (level < max && pool >= generalXpToNext(data, level)) {
    pool -= generalXpToNext(data, level);
    level += 1;
  }
  return { ...general, level, xp: level >= max ? 0 : pool };
}

// What a general adds to the troops it leads.
export function generalBonuses(data: GameData, general: GeneralState): Record<string, number> {
  const out: Record<string, number> = {};
  for (const [key, value] of Object.entries(data.heroes.generals.effectsPerLevel)) out[key] = value * general.level;
  return out;
}

// How many generals a player may have: per Hero's Hall, one plus one every
// few of its levels.
export function generalLimit(data: GameData, hallLevels: readonly number[]): number {
  const g = data.heroes.generals;
  return hallLevels.filter((l) => l > 0).reduce((n, l) => n + g.perHall + Math.floor((l - 1) / g.hallLevelsPerGeneral), 0);
}

// What the next general costs a player who has `owned` already.
export function recruitCost(data: GameData, owned: number): Resources {
  const g = data.heroes.generals;
  return mapResources((kind) => Math.round(g.cost[kind] * g.costGrowth ** owned));
}

export function recruitMs(data: GameData, worldSpeed: number): number {
  return Math.round((data.heroes.generals.recruitHours * 3_600_000) / worldSpeed);
}

// The Hero's Hall in a village shortens the hero's wounds healed there.
export function hallRecovery(data: GameData, hallLevel: number): number {
  if (hallLevel <= 0) return 1;
  return Math.max(0.1, 1 - data.heroes.generals.hallRecoveryPerLevel * hallLevel);
}

// Checks a recruit: a Hero's Hall in the village and room under the limit.
export function checkRecruit(data: GameData, input: { hallLevel: number; hallLevels: readonly number[]; owned: number }): void {
  if (input.hallLevel < 1) throw new RuleError("Generals are recruited at a Hero's Hall");
  const limit = generalLimit(data, input.hallLevels);
  if (input.owned >= limit) throw new RuleError(`Your Hero's Halls keep ${limit} ${limit === 1 ? 'general' : 'generals'}; raise one to recruit more`);
}
