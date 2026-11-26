// Army groups (data/armies.json groups): what a group should hold, and what
// it still lacks. The scheduler recruits it (scheduler/armyGroups.ts).
import type { GameData } from '../data/index.js';
import { RuleError } from '../errors.js';
import { total, validateArmy } from './armies.js';
import type { Units } from './training.js';

// A group's name: the one given, trimmed, or "<home>'s Army".
export function groupName(name: string | null | undefined, homeName: string): string {
  const given = (name ?? '').trim();
  if (given.length > 32) throw new RuleError('A name is at most 32 letters');
  return given || `${homeName}'s Army`;
}

// The troops a group should hold, by unit in name order: units that march
// with armies, whole numbers, at least one soldier, at most maxUnits.
export function validateComposition(data: GameData, composition: Units): Record<string, number> {
  const army = validateArmy(data, composition, 'hold');
  if (total(army) > data.armies.groups.maxUnits) throw new RuleError(`A group holds at most ${data.armies.groups.maxUnits} troops`);
  return Object.fromEntries(Object.keys(army).sort().map((unit) => [unit, army[unit]!]));
}

// What the group lacks of each unit (in name order), counting the troops in
// its army and those already on their way to it (in training or marching).
export function missingUnits(composition: Units, have: Units, coming: Units): Record<string, number> {
  const out: Record<string, number> = {};
  for (const unit of Object.keys(composition).sort()) {
    const n = (composition[unit] ?? 0) - (have[unit] ?? 0) - (coming[unit] ?? 0);
    if (n > 0) out[unit] = n;
  }
  return out;
}

// Ever smaller tries at a batch of `n`: n, half of it, ... down to 1 (the
// first that can be paid for is trained).
export function batchTries(n: number, maxBatch: number): number[] {
  const out: number[] = [];
  for (let k = Math.min(n, maxBatch); k >= 1; k = Math.floor(k / 2)) out.push(k);
  return out;
}
