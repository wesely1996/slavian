// Army slots (units.json armySlots): every unit takes its `slots` of its
// owner's army slots; each standing village gives `base` plus
// `perHallLevel` for each Elder's Hall level. No unit is trained beyond them.
import type { GameData } from '../data/index.js';
import { RuleError } from '../errors.js';
import { HALL } from './village.js';

type Units = Readonly<Record<string, number>>;

// The slots these units take.
export function unitSlots(data: GameData, units: Units): number {
  let n = 0;
  for (const [unit, count] of Object.entries(units)) n += count * (data.units.units[unit]?.slots ?? 0);
  return n;
}

// The slots a player's standing villages give.
export function slotCap(data: GameData, villages: readonly { ruin?: unknown; state: { levels: Readonly<Record<string, number>> } }[]): number {
  const rules = data.units.armySlots;
  return villages.filter((v) => !v.ruin).reduce((n, v) => n + rules.base + rules.perHallLevel * (v.state.levels[HALL] ?? 0), 0);
}

// The slots a player's troops take: garrisons and training queues, armies
// still out, and caravans' escorts on the road.
export function slotsUsed(
  data: GameData,
  input: {
    villages: readonly { state: { garrison: Units; training: readonly { unit: string; count: number }[] } }[];
    armies: readonly { status: string; units: Units }[];
    caravans: readonly { status: string; escort: Units }[];
  },
): number {
  let n = 0;
  for (const v of input.villages) {
    n += unitSlots(data, v.state.garrison);
    for (const batch of v.state.training) n += batch.count * (data.units.units[batch.unit]?.slots ?? 0);
  }
  for (const a of input.armies) if (a.status !== 'done') n += unitSlots(data, a.units);
  for (const c of input.caravans) if (c.status !== 'done') n += unitSlots(data, c.escort);
  return n;
}

// Training `count` more of `unit` must fit in the slots left.
export function checkSlots(data: GameData, slots: { used: number; cap: number }, unit: string, count: number): void {
  const need = count * (data.units.units[unit]?.slots ?? 0);
  if (need === 0 || slots.used + need <= slots.cap) return;
  const left = Math.max(0, slots.cap - slots.used);
  throw new RuleError(
    `Your army has ${left} of ${slots.cap} slots free; ${count} ${data.units.units[unit]?.name ?? unit} take ${need}. Raise an Elder's Hall or found a village for more.`,
  );
}
