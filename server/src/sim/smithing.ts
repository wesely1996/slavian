// The Blacksmith (data/smithing.json): each player forges improvements for
// their own units, one at a time; every level of a line adds perLevel to
// that unit's stat, for all the player's villages and armies.
import type { Affliction, GameData, SmithLine } from '../data/index.js';
import { AFFLICTIONS, SMITH_LINES } from '../data/index.js';
import { RuleError } from '../errors.js';
import { mapResources, type Resources } from './resources.js';
import { bonus, type Bonuses } from './research.js';

export const BLACKSMITH = 'blacksmith';

// A player's forged levels: unit → line → level.
export type Smithing = Record<string, Partial<Record<SmithLine, number>>>;

// The forging under way: which unit's line, to which level, done when.
export interface SmithWork {
  unit: string;
  line: SmithLine;
  level: number;
  villageId: number;
  completesAt: string;
}

// A line that forges an affliction (burn, poison) rather than a stat.
export function isAffliction(line: string): line is Affliction {
  return (AFFLICTIONS as readonly string[]).includes(line);
}

// The lines a unit can be improved along: a stat it has (speed for any
// unit that moves), and an affliction for the families (or engines) it
// serves, for a unit that strikes and doesn't already carry it.
export function smithLines(data: GameData, unit: string): SmithLine[] {
  const def = data.units.units[unit];
  if (!def) return [];
  return SMITH_LINES.filter((line) => {
    if (!isAffliction(line)) return (def[line] ?? 0) > 0;
    const rules = data.smithing.lines[line];
    const serves = (rules.families ?? []).includes(def.family) || (rules.engines === true && def.engine === true);
    return serves && def.attack > 0 && !(def.inflicts ?? []).includes(line);
  });
}

// How many levels a line has, and the Blacksmith level each needs.
export function smithLineLevels(data: GameData, line: SmithLine): number {
  return data.smithing.lines[line].levels ?? data.smithing.levels;
}

export function smithyLevelFor(data: GameData, line: SmithLine, level: number): number {
  return (data.smithing.lines[line].smithyLevels ?? data.smithing.smithyLevels)[level - 1] ?? 1;
}

// The level a line's `level` is priced and timed as.
function pricedLevel(data: GameData, line: SmithLine, level: number): number {
  return (data.smithing.lines[line].costLevel ?? 1) + level - 1;
}

export function smithLevel(smithing: Smithing, unit: string, line: SmithLine): number {
  return smithing[unit]?.[line] ?? 0;
}

// What forging `unit`'s `line` to `level` costs and how long it takes (ms;
// `smithTime` the forging village's bonus, from its Blacksmith). Blessed by
// the forge god (`blessed`), less of both (events.json blessings.forge).
export function smithCost(data: GameData, unit: string, line: SmithLine, level: number, blessed = false): Resources {
  const def = data.units.units[unit]!;
  const priced = pricedLevel(data, line, level);
  const factor = blessed ? data.events.blessings.forge.costFactor : 1;
  return mapResources((k) => Math.round(def.cost[k] * data.smithing.costFactor * priced * factor));
}

export function smithMs(data: GameData, unit: string, line: SmithLine, level: number, worldSpeed: number, bonuses: Bonuses = {}, blessed = false): number {
  const def = data.units.units[unit]!;
  const { base, perTier } = data.smithing.hours;
  const hours = (base + perTier * def.requiresLevel) * pricedLevel(data, line, level) * (blessed ? data.events.blessings.forge.timeFactor : 1);
  return Math.round((hours * 3_600_000 * Math.max(0.1, 1 + bonus(bonuses, 'smithTime'))) / worldSpeed);
}

// Whether `unit` is forged to the last level of every line it has.
export function smithedOut(data: GameData, smithing: Smithing, unit: string): boolean {
  const lines = smithLines(data, unit);
  return lines.length > 0 && lines.every((line) => smithLevel(smithing, unit, line) >= smithLineLevels(data, line));
}

// Why `unit`'s `line` can't be forged to its next level from a village
// with a Blacksmith of `smithyLevel` (throws a RuleError); the next level.
export function nextSmithLevel(data: GameData, smithing: Smithing, unit: string, line: string, smithyLevel: number, busy: boolean): number {
  const def = data.units.units[unit];
  if (!def) throw new RuleError(`Unknown unit "${unit}"`);
  if (!(SMITH_LINES as readonly string[]).includes(line) || !smithLines(data, unit).includes(line as SmithLine)) {
    throw new RuleError(`The Blacksmith can't improve the ${def.name}'s ${line}`);
  }
  if (busy) throw new RuleError('Your Blacksmith is busy; one improvement at a time');
  const level = smithLevel(smithing, unit, line as SmithLine) + 1;
  if (level > smithLineLevels(data, line as SmithLine)) throw new RuleError(`The ${def.name}'s ${data.smithing.lines[line as SmithLine].name.toLowerCase()} is as good as it gets`);
  const needs = smithyLevelFor(data, line as SmithLine, level);
  if (smithyLevel < needs) throw new RuleError(`That needs a Blacksmith of level ${needs}`);
  return level;
}

// What the forged levels give: per unit, its stats' bonuses
// (attack.unit.<id>, defense.unit.<id>, health.unit.<id>, speed.unit.<id>),
// and 1 for each affliction its blows now carry (burn.unit.<id>, poison.unit.<id>).
export function smithingBonuses(data: GameData, smithing: Smithing): Record<string, number> {
  const out: Record<string, number> = {};
  for (const [unit, lines] of Object.entries(smithing).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))) {
    for (const line of SMITH_LINES) {
      const level = lines[line] ?? 0;
      if (level > 0) out[`${line}.unit.${unit}`] = isAffliction(line) ? 1 : level * data.smithing.perLevel;
    }
  }
  return out;
}

// A unit's speed with its forged harness.
export function unitSpeed(data: GameData, unit: string, bonuses: Bonuses = {}): number {
  return (data.units.units[unit]?.speed ?? 1) * (1 + bonus(bonuses, `speed.unit.${unit}`));
}
