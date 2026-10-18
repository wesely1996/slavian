// Heroes: one per player, leading the garrison of the village they stand
// in. Skills and gear use the same effect keys as research.
import type { GameData, HeroSlot } from '../data/index.js';
import { RuleError } from '../errors.js';
import { createRng } from './rng.js';
import type { Bonuses } from './research.js';

export type HeroStatus = 'home' | 'traveling' | 'wounded' | 'with_army';

export interface HeroState {
  readonly name: string;
  readonly level: number;
  readonly xp: number;
  readonly skillPoints: number;
  readonly skills: Readonly<Record<string, number>>;
  readonly gear: Readonly<Partial<Record<HeroSlot, string>>>;
  readonly inventory: readonly string[];
}

export function newHero(data: GameData, seed: number, accountId: number): HeroState {
  const names = data.heroes.names;
  const name = names[Math.floor(createRng((seed ^ Math.imul(accountId + 1, 0x9e3779b1)) >>> 0)() * names.length)]!;
  return { name, level: 1, xp: 0, skillPoints: 0, skills: {}, gear: {}, inventory: [] };
}

// XP needed to go from `level` to the next.
export function xpToNext(data: GameData, level: number): number {
  const { base, growth } = data.heroes.levelXp;
  return Math.round(base * growth ** (level - 1));
}

// Adds XP, levelling up (one skill point per level) as far as it reaches.
export function gainXp(data: GameData, hero: HeroState, xp: number): HeroState {
  let { level, skillPoints } = hero;
  let pool = hero.xp + Math.max(0, Math.floor(xp));
  while (level < data.heroes.maxLevel && pool >= xpToNext(data, level)) {
    pool -= xpToNext(data, level);
    level += 1;
    skillPoints += 1;
  }
  return { ...hero, level, skillPoints, xp: level >= data.heroes.maxLevel ? 0 : pool };
}

export function learnSkill(data: GameData, hero: HeroState, skill: string): HeroState {
  const def = data.heroes.skills[skill];
  if (!def) throw new RuleError(`Unknown skill "${skill}"`);
  if (hero.skillPoints < 1) throw new RuleError('No skill points left; they come with levels');
  const rank = hero.skills[skill] ?? 0;
  if (rank >= def.maxRank) throw new RuleError(`${def.name} is already at its highest rank`);
  return { ...hero, skillPoints: hero.skillPoints - 1, skills: { ...hero.skills, [skill]: rank + 1 } };
}

// Puts an item from the pack into its slot; what was there goes back.
export function equip(data: GameData, hero: HeroState, item: string): HeroState {
  const def = data.heroes.items[item];
  if (!def || !hero.inventory.includes(item)) throw new RuleError('The hero has no such item');
  const previous = hero.gear[def.slot];
  const inventory = hero.inventory.filter((i) => i !== item);
  return { ...hero, gear: { ...hero.gear, [def.slot]: item }, inventory: previous ? [...inventory, previous] : inventory };
}

export function unequip(hero: HeroState, slot: HeroSlot): HeroState {
  const item = hero.gear[slot];
  if (!item) throw new RuleError('Nothing in that slot');
  const gear = { ...hero.gear };
  delete gear[slot];
  return { ...hero, gear, inventory: [...hero.inventory, item] };
}

// What the hero adds: skills by rank, gear, and full sets.
export function heroBonuses(data: GameData, hero: HeroState): Record<string, number> {
  const bonuses: Record<string, number> = {};
  const add = (effects: Readonly<Record<string, number>>, times = 1) => {
    for (const [key, value] of Object.entries(effects)) bonuses[key] = (bonuses[key] ?? 0) + value * times;
  };
  for (const [skill, rank] of Object.entries(hero.skills)) add(data.heroes.skills[skill]?.effectsPerRank ?? {}, rank);
  const worn = new Set(Object.values(hero.gear));
  for (const item of worn) add(data.heroes.items[item]?.effects ?? {});
  for (const set of Object.values(data.heroes.sets)) if (set.items.every((item) => worn.has(item))) add(set.effects);
  return bonuses;
}

export function combine(a: Bonuses, b: Bonuses): Record<string, number> {
  const sum: Record<string, number> = { ...a };
  for (const [key, value] of Object.entries(b)) sum[key] = (sum[key] ?? 0) + value;
  return sum;
}

// A beaten horde may leave gear behind: one item the hero doesn't have yet.
export function rollDrop(data: GameData, hero: HeroState, seed: number, battleId: number): string | null {
  const rng = createRng((seed ^ Math.imul(battleId + 1, 0x2545f491) ^ 0xd2) >>> 0);
  if (rng() >= data.heroes.dropChance) return null;
  const owned = new Set([...hero.inventory, ...Object.values(hero.gear)]);
  const candidates = Object.keys(data.heroes.items).filter((item) => !owned.has(item)).sort();
  if (!candidates.length) return null;
  return candidates[Math.floor(rng() * candidates.length)]!;
}

export function woundMs(data: GameData, worldSpeed: number): number {
  return Math.round((data.heroes.woundHours * 3_600_000) / worldSpeed);
}
