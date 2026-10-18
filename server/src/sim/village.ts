import type { BuildingDef, GameData, Stance } from '../data/index.js';
import { RuleError } from '../errors.js';
import {
  mapResources,
  spend,
  take,
  withRates,
  type ResourceLedger,
  type Resources,
} from './resources.js';
import {
  addUnits,
  allUnits,
  batchCompletesAt,
  perUnitMs,
  settleTraining,
  upkeepPerHour,
  type TrainingBatch,
  type Units,
} from './training.js';

// A village is laid out as plots: resource fields around it ("f0"…) and
// building slots in its center ("c0"…, the first holding the Elder's Hall).
// Each plot holds one building at some level; fields never change type.
export interface Plot {
  readonly building: string | null;
  readonly level: number;
}
export type Plots = Readonly<Record<string, Plot>>;

export interface QueuedBuild {
  readonly plot: string;
  readonly building: string;
  readonly targetLevel: number;
  readonly startsAt: Date;
  readonly completesAt: Date;
}

export interface VillageState {
  readonly plots: Plots;
  // Highest level of each building, derived from plots (what unit and
  // building requirements check).
  readonly levels: Readonly<Record<string, number>>;
  readonly ledger: ResourceLedger;
  readonly queue: readonly QueuedBuild[];
  readonly garrison: Units;
  readonly training: readonly TrainingBatch[];
  // Units away from home on a mission (scouts). They still eat.
  readonly away: Units;
  // How the garrison fights when the village is attacked.
  readonly stance: Stance;
}

const MS_PER_SECOND = 1000;
export const HALL = 'elder_hall';
export const HALL_PLOT = 'c0';

function buildingDef(data: GameData, building: string): BuildingDef {
  const def = data.buildings.buildings[building];
  if (!def) throw new RuleError(`Unknown building "${building}"`);
  return def;
}

export function fieldPlot(index: number): string {
  return `f${index}`;
}

export function centerPlot(index: number): string {
  return `c${index}`;
}

export function initialPlots(data: GameData): Record<string, Plot> {
  const { fields, centerSlots } = data.buildings.village;
  const plots: Record<string, Plot> = {};
  fields.forEach((building, i) => (plots[fieldPlot(i)] = { building, level: 0 }));
  for (let i = 0; i < centerSlots; i++) plots[centerPlot(i)] = { building: null, level: 0 };
  plots[HALL_PLOT] = { building: HALL, level: 1 };
  return plots;
}

export function levelsOf(plots: Plots): Record<string, number> {
  const levels: Record<string, number> = {};
  for (const plot of Object.values(plots)) {
    if (plot.building && plot.level > 0) levels[plot.building] = Math.max(levels[plot.building] ?? 0, plot.level);
  }
  return levels;
}

// Center slots usable at an Elder's Hall level.
export function unlockedSlots(data: GameData, hallLevel: number): number {
  const v = data.buildings.village;
  return Math.min(v.centerSlots, v.slotsUnlockedAtStart + v.slotsPerHallLevel * Math.max(0, hallLevel - 1));
}

export function buildQueueLimit(data: GameData, hallLevel: number): number {
  const v = data.buildings.village;
  return v.baseQueueLimit + Math.floor(hallLevel / v.hallLevelsPerQueueSlot);
}

export function levelCost(def: BuildingDef, targetLevel: number): Resources {
  const factor = def.costGrowth ** (targetLevel - 1);
  return mapResources((kind) => Math.round(def.cost[kind] * factor));
}

// Real-time seconds; world speed divides all durations, and a bigger
// Elder's Hall builds faster.
export function buildSeconds(def: BuildingDef, targetLevel: number, worldSpeed: number, hallSpeedup = 1): number {
  return (def.buildSeconds * def.timeGrowth ** (targetLevel - 1) * hallSpeedup) / worldSpeed;
}

export function hallSpeedup(data: GameData, hallLevel: number): number {
  return data.buildings.village.hallBuildSpeedup ** Math.max(0, hallLevel - 1);
}

// Real-time rates; world speed multiplies production.
export function productionPerHour(data: GameData, plots: Plots, worldSpeed: number): Resources {
  const rates = { ...data.buildings.village.baseProductionPerHour };
  for (const plot of Object.values(plots)) {
    if (!plot.building || plot.level <= 0) continue;
    const production = buildingDef(data, plot.building).production;
    if (production) rates[production.resource] += production.basePerHour * production.growth ** (plot.level - 1);
  }
  return mapResources((kind) => rates[kind] * worldSpeed);
}

// Every unit the village feeds: at home, in training and away.
export function unitsFed(state: Pick<VillageState, 'garrison' | 'training' | 'away'>): Record<string, number> {
  return addUnits(allUnits(state.garrison, state.training), state.away);
}

// Net rates: production minus grain upkeep for every unit the village
// feeds. Grain can go negative; the ledger floors amounts at zero.
export function ratesPerHour(data: GameData, plots: Plots, units: Units, worldSpeed: number): Resources {
  const rates = productionPerHour(data, plots, worldSpeed);
  return { ...rates, grain: rates.grain - upkeepPerHour(data, units, worldSpeed) };
}

export function capacity(data: GameData, levels: VillageState['levels']): Resources {
  const storehouse = data.buildings.buildings.storehouse;
  const level = levels.storehouse ?? 0;
  const cap = data.buildings.village.baseCapacity * (storehouse?.capacityGrowth ?? 1) ** level;
  return mapResources(() => cap);
}

export function newVillage(data: GameData, at: Date, worldSpeed: number): VillageState {
  const plots = initialPlots(data);
  const levels = levelsOf(plots);
  return {
    plots,
    levels,
    queue: [],
    garrison: {},
    training: [],
    away: {},
    stance: 'balanced',
    ledger: {
      amounts: { ...data.buildings.village.startingResources },
      ratesPerHour: productionPerHour(data, plots, worldSpeed),
      capacity: capacity(data, levels),
      settledAt: at,
    },
  };
}

// What a plot will hold once everything already queued completes.
function plannedPlot(state: VillageState, plot: string): Plot {
  const queued = state.queue.filter((item) => item.plot === plot).at(-1);
  return queued ? { building: queued.building, level: queued.targetLevel } : state.plots[plot]!;
}

export interface BuildOrder {
  // Which plot to build on or upgrade.
  readonly plot?: string;
  // The building: required for an empty slot; with no plot, the plot is
  // picked for it (older clients only send this).
  readonly building?: string;
}

// Turns an order into a plot. With only a building: its existing plot, the
// lowest of its fields, or the first free unlocked slot.
function resolvePlot(data: GameData, state: VillageState, order: BuildOrder, hallLevel: number): string {
  if (order.plot) return order.plot;
  if (!order.building) throw new RuleError('Say which plot or building to build');
  const def = buildingDef(data, order.building);
  const ids = Object.keys(state.plots);
  if (def.kind === 'field') {
    const fields = ids.filter((id) => plannedPlot(state, id).building === order.building);
    fields.sort((a, b) => plannedPlot(state, a).level - plannedPlot(state, b).level);
    if (!fields[0]) throw new RuleError(`This village has no ${def.name} fields`);
    return fields[0];
  }
  const existing = ids.find((id) => plannedPlot(state, id).building === order.building);
  if (existing) return existing;
  const free = ids.find((id) => isUnlockedSlot(data, id, hallLevel) && plannedPlot(state, id).building === null);
  if (!free) throw new RuleError('No free building slot; upgrade the Elder\'s Hall');
  return free;
}

function isUnlockedSlot(data: GameData, plot: string, hallLevel: number): boolean {
  return plot.startsWith('c') && Number(plot.slice(1)) < unlockedSlots(data, hallLevel);
}

// Pays for and queues a construction or upgrade. Builds run one after
// another, so the new item starts when the last queued one completes.
export function queueBuild(
  data: GameData,
  state: VillageState,
  order: BuildOrder | string,
  at: Date,
  worldSpeed: number,
): { state: VillageState; queued: QueuedBuild } {
  const request: BuildOrder = typeof order === 'string' ? { building: order } : order;
  const hallLevel = state.levels[HALL] ?? 0;
  if (state.queue.length >= buildQueueLimit(data, hallLevel)) throw new RuleError('Build queue is full');

  const plot = resolvePlot(data, state, request, hallLevel);
  const current = state.plots[plot];
  if (!current) throw new RuleError(`No plot "${plot}"`);
  const planned = plannedPlot(state, plot);
  let building: string;
  if (planned.building) {
    building = planned.building;
    if (request.building && request.building !== building) {
      throw new RuleError(`That plot holds a ${buildingDef(data, building).name}`);
    }
  } else {
    if (!isUnlockedSlot(data, plot, hallLevel)) throw new RuleError('That slot is locked; upgrade the Elder\'s Hall');
    if (!request.building) throw new RuleError('Say which building to construct');
    building = request.building;
    const def = buildingDef(data, building);
    if (def.kind !== 'center') throw new RuleError(`${def.name} is built on fields, not in the village`);
    const taken = Object.keys(state.plots).some((id) => id !== plot && plannedPlot(state, id).building === building);
    if (taken) throw new RuleError(`This village already has a ${def.name}`);
  }

  const def = buildingDef(data, building);
  const targetLevel = planned.level + 1;
  if (targetLevel > def.maxLevel) throw new RuleError(`${def.name} is already at max level`);

  const ledger = spend(state.ledger, at, levelCost(def, targetLevel));
  const startsAt = state.queue.at(-1)?.completesAt ?? at;
  const seconds = buildSeconds(def, targetLevel, worldSpeed, hallSpeedup(data, hallLevel));
  const completesAt = new Date(startsAt.getTime() + seconds * MS_PER_SECOND);
  const queued: QueuedBuild = { plot, building, targetLevel, startsAt, completesAt };
  return { state: { ...state, ledger, queue: [...state.queue, queued] }, queued };
}

// Applies the head of the queue. `at` is the scheduled completion time, not
// the time the event happens to be processed.
export function completeBuild(
  data: GameData,
  state: VillageState,
  plot: string,
  targetLevel: number,
  at: Date,
  worldSpeed: number,
): VillageState {
  const [head, ...rest] = state.queue;
  if (!head || head.plot !== plot || head.targetLevel !== targetLevel) {
    throw new RuleError(`Build on ${plot} to level ${targetLevel} is not at the head of the queue`);
  }
  const plots = { ...state.plots, [plot]: { building: head.building, level: targetLevel } };
  const levels = levelsOf(plots);
  return {
    ...state,
    plots,
    levels,
    queue: rest,
    ledger: withRates(state.ledger, at, ratesPerHour(data, plots, unitsFed(state), worldSpeed), capacity(data, levels)),
  };
}

// Villages saved before plots existed only had a level per building:
// put each on its first field of that type, or a center slot.
export function plotsFromLegacyLevels(data: GameData, levels: Record<string, number>): Record<string, Plot> {
  const plots = initialPlots(data);
  let nextSlot = 1;
  for (const [building, level] of Object.entries(levels)) {
    const def = data.buildings.buildings[building];
    if (!def || level <= 0) continue;
    if (building === HALL) {
      plots[HALL_PLOT] = { building, level };
    } else if (def.kind === 'field') {
      const id = Object.keys(plots).find((key) => plots[key]!.building === building);
      if (id) plots[id] = { building, level };
    } else {
      plots[centerPlot(nextSlot++)] = { building, level };
    }
  }
  return plots;
}

// Pays for and queues `count` units. Batches train one after another; the
// new units start eating as soon as they are drafted.
export function queueTraining(
  data: GameData,
  state: VillageState,
  unit: string,
  count: number,
  at: Date,
  worldSpeed: number,
): { state: VillageState; batch: TrainingBatch } {
  const def = data.units.units[unit];
  if (!def) throw new RuleError(`Unknown unit "${unit}"`);
  if (!Number.isInteger(count) || count < 1 || count > data.units.maxBatch) {
    throw new RuleError(`Train between 1 and ${data.units.maxBatch} at a time`);
  }
  const buildingLevel = state.levels[def.building] ?? 0;
  if (buildingLevel < def.requiresLevel) {
    throw new RuleError(`${def.name} needs ${buildingDef(data, def.building).name} level ${def.requiresLevel}`);
  }
  if (state.training.length >= data.units.trainingQueueLimit) throw new RuleError('Training queue is full');

  const cost = mapResources((kind) => def.cost[kind] * count);
  const paid = spend(state.ledger, at, cost);
  const last = state.training.at(-1);
  const startsAt = last && batchCompletesAt(last) > at ? batchCompletesAt(last) : at;
  const batch: TrainingBatch = { unit, count, startsAt, perUnitMs: perUnitMs(data, unit, buildingLevel, worldSpeed) };
  const training = [...state.training, batch];
  const ledger = withRates(paid, at, ratesPerHour(data, state.plots, unitsFed({ ...state, training }), worldSpeed));
  return { state: { ...state, ledger, training }, batch };
}

// Moves units trained by `at` into the garrison. Idempotent.
export function completeTraining(state: VillageState, at: Date): VillageState {
  return { ...state, ...settleTraining(state.garrison, state.training, at) };
}

export class NotEnoughUnitsError extends RuleError {}

// Sends `count` units of `unit` away from home. Units finished training by
// `at` count as home.
export function sendAway(state: VillageState, unit: string, count: number, at: Date): VillageState {
  const settled = completeTraining(state, at);
  const home = settled.garrison[unit] ?? 0;
  if (home < count) throw new NotEnoughUnitsError(`Only ${home} ${unit} at home`);
  return {
    ...settled,
    garrison: { ...settled.garrison, [unit]: home - count },
    away: addUnits(settled.away, { [unit]: count }),
  };
}

// Units away that will never come back (killed): they stop eating now.
export function loseAway(data: GameData, state: VillageState, unit: string, count: number, at: Date, worldSpeed: number): VillageState {
  const away = { ...state.away, [unit]: Math.max(0, (state.away[unit] ?? 0) - count) };
  const next = { ...state, away };
  return { ...next, ledger: withRates(state.ledger, at, ratesPerHour(data, state.plots, unitsFed(next), worldSpeed)) };
}

// Units coming home from a mission.
export function returnHome(state: VillageState, unit: string, count: number): VillageState {
  return {
    ...state,
    away: { ...state.away, [unit]: Math.max(0, (state.away[unit] ?? 0) - count) },
    garrison: addUnits(state.garrison, { [unit]: count }),
  };
}

// Garrison losses in battle: the dead stop eating from `at`.
export function loseGarrison(data: GameData, state: VillageState, losses: Units, at: Date, worldSpeed: number): VillageState {
  const garrison: Record<string, number> = { ...state.garrison };
  for (const [unit, count] of Object.entries(losses)) garrison[unit] = Math.max(0, (garrison[unit] ?? 0) - count);
  const next = { ...state, garrison };
  return { ...next, ledger: withRates(state.ledger, at, ratesPerHour(data, state.plots, unitsFed(next), worldSpeed)) };
}

export function plunder(state: VillageState, loot: Resources, at: Date): VillageState {
  return { ...state, ledger: take(state.ledger, at, loot) };
}
