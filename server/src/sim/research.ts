// Research effects: each finished tech adds its effects to its player's
// bonuses, which every one of their villages carries.
import type { GameData, ResearchData, UnitFamily } from '../data/index.js';
import { RuleError } from '../errors.js';
import type { ResourceKind } from './resources.js';

export type Bonuses = Readonly<Record<string, number>>;
export const ACADEMY = 'academy';

// Effects of a set of finished techs, added up.
export function bonusesOf(data: GameData, techs: Iterable<string>): Record<string, number> {
  const bonuses: Record<string, number> = {};
  for (const tech of techs) {
    for (const [key, value] of Object.entries(data.research.techs[tech]?.effects ?? {})) {
      bonuses[key] = (bonuses[key] ?? 0) + value;
    }
  }
  return bonuses;
}

export function bonus(bonuses: Bonuses, key: string): number {
  return bonuses[key] ?? 0;
}

// Multiplier for producing `kind`.
export function productionFactor(bonuses: Bonuses, kind: ResourceKind): number {
  return 1 + bonus(bonuses, `production.${kind}`) + bonus(bonuses, 'production.all');
}

// Multiplier for a duration: never below a tenth.
export function timeFactor(bonuses: Bonuses, key: 'buildTime' | 'trainTime'): number {
  return Math.max(0.1, 1 + bonus(bonuses, key));
}

// Training time for `unit`: the general bonus and its own (trainTime.<unit>).
export function trainFactor(bonuses: Bonuses, unit: string): number {
  return Math.max(0.1, 1 + bonus(bonuses, 'trainTime') + bonus(bonuses, `trainTime.${unit}`));
}

export function attackFactor(bonuses: Bonuses, family: UnitFamily): number {
  return 1 + bonus(bonuses, `attack.${family}`) + bonus(bonuses, 'attack.all');
}

export function defenseFactor(bonuses: Bonuses, family: UnitFamily, home: boolean): number {
  return 1 + bonus(bonuses, `defense.${family}`) + bonus(bonuses, 'defense.all') + (home ? bonus(bonuses, 'homeDefense') : 0);
}

// Why a player can't start `tech` (null when they can).
export function researchProblem(
  data: GameData,
  tech: string,
  input: { academyLevel: number; done: ReadonlySet<string>; researching: boolean; scrolls?: ReadonlySet<string> },
): string | null {
  const def: ResearchData['techs'][string] | undefined = data.research.techs[tech];
  if (!def) return `Unknown tech "${tech}"`;
  if (input.done.has(tech)) return `${def.name} is already known`;
  if (input.researching) return 'Your scholars are busy; one tech at a time';
  if (def.requiresScroll && !input.scrolls?.has(def.requiresScroll)) {
    return `${def.name} needs the ${data.lore.scrolls[def.requiresScroll]?.name ?? def.requiresScroll} scroll`;
  }
  if (input.academyLevel < def.academyLevel) return `${def.name} needs an Academy of level ${def.academyLevel}`;
  const missing = def.requires.filter((t) => !input.done.has(t)).map((t) => data.research.techs[t]!.name);
  if (missing.length) return `${def.name} needs ${missing.join(' and ')} first`;
  return null;
}

export function researchMs(data: GameData, tech: string, worldSpeed: number, bonuses: Bonuses = {}): number {
  const def = data.research.techs[tech];
  if (!def) throw new RuleError(`Unknown tech "${tech}"`);
  return Math.round((def.seconds * 1000 * Math.max(0.1, 1 + bonus(bonuses, 'researchTime'))) / worldSpeed);
}
