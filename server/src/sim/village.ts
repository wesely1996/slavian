import type { BuildingDef, GameData, Stance, TerrainId } from '../data/index.js';
import { clanName, hasClan, villageBonuses } from './clans.js';
import { RuleError } from '../errors.js';
import { hex, hexDistance, hexKey, type Hex } from './hex.js';
import { bonus, productionFactor, timeFactor, trainFactor, type Bonuses } from './research.js';
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

// A village is laid out as plots: resource fields around it ("f0"…),
// building slots in its center ("c0"…, the first holding the Elder's Hall)
// and outposts on map hexes near it ("o3,-2"). Each plot holds one building
// at some level; fields never change type. An outpost at level 0 is being
// built or lies in ruins.
export interface Plot {
  readonly building: string | null;
  readonly level: number;
  // Outposts: the terrain of their hex, which decides what they gather,
  // and the best level they ever reached (what a rebuild order restores).
  readonly terrain?: TerrainId;
  readonly peak?: number;
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
  // A horde is fighting at the gates: outposts stop producing.
  readonly besieged: boolean;
  // Grain per hour (at world speed 1) every village after an owner's
  // first pays for its administration.
  readonly adminUpkeep: number;
  // The owner's research effects (see research.ts).
  readonly bonuses: Bonuses;
}

const MS_PER_SECOND = 1000;
export const HALL = 'elder_hall';
export const HALL_PLOT = 'c0';
export const OUTPOST = 'outpost';

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

export function outpostPlot(cell: Hex): string {
  return `o${cell.q},${cell.r}`;
}

// The hex of an outpost plot id, or null for other plots.
export function outpostHex(plot: string): Hex | null {
  const match = /^o(-?\d+),(-?\d+)$/.exec(plot);
  return match ? hex(Number(match[1]), Number(match[2])) : null;
}

export function outpostPlots(plots: Plots): string[] {
  return Object.keys(plots).filter((id) => outpostHex(id) !== null);
}

export function initialPlots(data: GameData): Record<string, Plot> {
  const { fields, centerSlots } = data.buildings.village;
  const plots: Record<string, Plot> = {};
  fields.forEach((building, i) => (plots[fieldPlot(i)] = { building, level: 0 }));
  for (let i = 0; i < centerSlots; i++) plots[centerPlot(i)] = { building: null, level: 0 };
  plots[HALL_PLOT] = { building: HALL, level: 1 };
  return plots;
}

// Highest level of each building in the village itself (outposts aside).
export function levelsOf(plots: Plots): Record<string, number> {
  const levels: Record<string, number> = {};
  for (const [id, plot] of Object.entries(plots)) {
    if (outpostHex(id) || !plot.building || plot.level <= 0) continue;
    levels[plot.building] = Math.max(levels[plot.building] ?? 0, plot.level);
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

export function outpostLimit(data: GameData, hallLevel: number): number {
  const v = data.buildings.village;
  return v.baseOutposts + Math.floor(hallLevel / v.hallLevelsPerOutpost);
}

// What an outpost gathers per hour (world speed applied); nothing at
// level 0 or on terrain without a yield.
export function outpostYield(def: BuildingDef, terrain: TerrainId | undefined, level: number, worldSpeed: number): Resources {
  const base = terrain ? def.yields?.[terrain] : undefined;
  const factor = level > 0 ? (def.yieldGrowth ?? 1) ** (level - 1) * worldSpeed : 0;
  return mapResources((kind) => (base?.[kind] ?? 0) * factor);
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

// Real-time rates; world speed multiplies production, research raises it.
// Outposts produce nothing while the village is besieged.
export function productionPerHour(
  data: GameData,
  plots: Plots,
  worldSpeed: number,
  besieged = false,
  bonuses: Bonuses = {},
): Resources {
  const rates = mapResources((kind) => data.buildings.village.baseProductionPerHour[kind] * worldSpeed);
  const outpostFactor = 1 + bonus(bonuses, 'outpostYield');
  for (const plot of Object.values(plots)) {
    if (!plot.building || plot.level <= 0) continue;
    const def = buildingDef(data, plot.building);
    if (def.production) {
      rates[def.production.resource] += def.production.basePerHour * def.production.growth ** (plot.level - 1) * worldSpeed;
    } else if (def.yields && !besieged) {
      const gathered = outpostYield(def, plot.terrain, plot.level, worldSpeed);
      for (const kind of Object.keys(rates) as (keyof Resources)[]) rates[kind] += gathered[kind] * outpostFactor;
    }
  }
  return mapResources((kind) => rates[kind] * productionFactor(bonuses, kind));
}

// Every unit the village feeds: at home, in training and away.
export function unitsFed(state: Pick<VillageState, 'garrison' | 'training' | 'away'>): Record<string, number> {
  return addUnits(allUnits(state.garrison, state.training), state.away);
}

// Net rates: production minus grain upkeep for every unit the village
// feeds. Grain can go negative; the ledger floors amounts at zero.
export function villageRates(
  data: GameData,
  state: Pick<VillageState, 'plots' | 'besieged' | 'garrison' | 'training' | 'away' | 'adminUpkeep' | 'bonuses'>,
  worldSpeed: number,
): Resources {
  const bonuses = villageBonuses(data, state);
  const rates = productionPerHour(data, state.plots, worldSpeed, state.besieged, bonuses);
  const troops = upkeepPerHour(data, unitsFed(state), worldSpeed) * Math.max(0, 1 + bonus(bonuses, 'upkeep'));
  const upkeep = troops + state.adminUpkeep * worldSpeed;
  return { ...rates, grain: rates.grain - upkeep };
}

export function capacity(data: GameData, levels: VillageState['levels'], bonuses: Bonuses = {}): Resources {
  const storehouse = data.buildings.buildings.storehouse;
  const level = levels.storehouse ?? 0;
  const cap = data.buildings.village.baseCapacity * (storehouse?.capacityGrowth ?? 1) ** level * (1 + bonus(bonuses, 'storage'));
  return mapResources(() => cap);
}

// A fresh village. Founded ones (after the first) bring their own
// starting stores and pay administration upkeep.
export function newVillage(
  data: GameData,
  at: Date,
  worldSpeed: number,
  founded: { startingResources: Resources; adminUpkeep: number; bonuses: Bonuses } | null = null,
): VillageState {
  const plots = initialPlots(data);
  const levels = levelsOf(plots);
  const state: Omit<VillageState, 'ledger'> = {
    plots,
    levels,
    queue: [],
    garrison: {},
    training: [],
    away: {},
    stance: 'balanced',
    besieged: false,
    adminUpkeep: founded?.adminUpkeep ?? 0,
    bonuses: founded?.bonuses ?? {},
  };
  return {
    ...state,
    ledger: {
      amounts: { ...(founded?.startingResources ?? data.buildings.village.startingResources) },
      ratesPerHour: villageRates(data, state, worldSpeed),
      capacity: capacity(data, levels, state.bonuses),
      settledAt: at,
    },
  };
}

// The owner's research changed: new rates and capacity from `at`.
export function withBonuses(data: GameData, state: VillageState, bonuses: Bonuses, at: Date, worldSpeed: number): VillageState {
  const next = { ...state, bonuses };
  return { ...next, ledger: withRates(state.ledger, at, villageRates(data, next, worldSpeed), capacity(data, state.levels, bonuses)) };
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
  if (def.kind === 'outpost') throw new RuleError('Pick a hex for the outpost');
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
    if (def.clan && !hasClan(state.bonuses, def.clan)) throw new RuleError(`Only ${clanName(data, def.clan)} can build a ${def.name}`);
    const taken = Object.keys(state.plots).some((id) => id !== plot && plannedPlot(state, id).building === building);
    if (taken) throw new RuleError(`This village already has a ${def.name}`);
  }

  const def = buildingDef(data, building);
  const targetLevel = planned.level + 1;
  if (targetLevel > def.maxLevel) throw new RuleError(`${def.name} is already at max level`);

  const ledger = spend(state.ledger, at, levelCost(def, targetLevel));
  const startsAt = state.queue.at(-1)?.completesAt ?? at;
  const seconds = buildSeconds(def, targetLevel, worldSpeed, hallSpeedup(data, hallLevel) * timeFactor(state.bonuses, 'buildTime'));
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
  const before = state.plots[plot];
  const built: Plot = outpostHex(plot)
    ? { ...before, building: head.building, level: targetLevel, peak: Math.max(before?.peak ?? 0, targetLevel) }
    : { ...before, building: head.building, level: targetLevel };
  const plots = { ...state.plots, [plot]: built };
  const levels = levelsOf(plots);
  const next = { ...state, plots, levels, queue: rest };
  return { ...next, ledger: withRates(state.ledger, at, villageRates(data, next, worldSpeed), capacity(data, levels, state.bonuses)) };
}

export interface OutpostSite {
  readonly cell: Hex;
  readonly terrain: TerrainId;
  // The owning village's hex.
  readonly home: Hex;
  // Hexes that already hold a village or anyone's outpost ("q,r" keys).
  readonly taken: ReadonlySet<string>;
}

// Claims a resource hex near the village and queues its outpost's first
// level, paid like any other build.
export function claimOutpost(
  data: GameData,
  state: VillageState,
  site: OutpostSite,
  at: Date,
  worldSpeed: number,
): { state: VillageState; queued: QueuedBuild } {
  const def = buildingDef(data, OUTPOST);
  const range = data.buildings.village.outpostRange;
  const distance = hexDistance(site.cell, site.home);
  if (distance === 0 || distance > range) throw new RuleError(`Outposts go within ${range} hexes of the village`);
  if (!def.yields?.[site.terrain]) {
    throw new RuleError(`Nothing to gather on ${data.terrain.terrain[site.terrain].name}`);
  }
  if (site.taken.has(hexKey(site.cell))) throw new RuleError('That hex is already taken');
  const limit = outpostLimit(data, state.levels[HALL] ?? 0);
  if (outpostPlots(state.plots).length >= limit) {
    throw new RuleError(`This village can hold ${limit} outpost${limit === 1 ? '' : 's'}; upgrade the Elder's Hall for more`);
  }
  const plot = outpostPlot(site.cell);
  const claimed = { ...state, plots: { ...state.plots, [plot]: { building: OUTPOST, level: 0, terrain: site.terrain } } };
  return queueBuild(data, claimed, { plot }, at, worldSpeed);
}

// Gives up an outpost (or its ruins). Not while it is being built.
export function abandonOutpost(data: GameData, state: VillageState, plot: string, at: Date, worldSpeed: number): VillageState {
  if (!outpostHex(plot) || !state.plots[plot]) throw new RuleError('No outpost there');
  if (state.queue.some((item) => item.plot === plot)) throw new RuleError('The outpost is being built; wait for it to finish');
  const plots = { ...state.plots };
  delete plots[plot];
  const next = { ...state, plots };
  return { ...next, ledger: withRates(state.ledger, at, villageRates(data, next, worldSpeed)) };
}

// A passing horde burns an outpost down a level; at level 0 it lies in
// ruins until rebuilt.
export function raidOutpost(data: GameData, state: VillageState, plot: string, at: Date, worldSpeed: number): VillageState {
  const current = state.plots[plot];
  if (!outpostHex(plot) || !current || current.level <= 0) return state;
  const plots = { ...state.plots, [plot]: { ...current, level: current.level - 1 } };
  const next = { ...state, plots };
  return { ...next, ledger: withRates(state.ledger, at, villageRates(data, next, worldSpeed)) };
}

export function setBesieged(data: GameData, state: VillageState, besieged: boolean, at: Date, worldSpeed: number): VillageState {
  if (state.besieged === besieged) return state;
  const next = { ...state, besieged };
  return { ...next, ledger: withRates(state.ledger, at, villageRates(data, next, worldSpeed)) };
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
  villagesOwned = 1,
): { state: VillageState; batch: TrainingBatch } {
  const def = data.units.units[unit];
  if (!def) throw new RuleError(`Unknown unit "${unit}"`);
  if (!Number.isInteger(count) || count < 1 || count > data.units.maxBatch) {
    throw new RuleError(`Train between 1 and ${data.units.maxBatch} at a time`);
  }
  if (def.clan && !hasClan(state.bonuses, def.clan)) throw new RuleError(`Only ${clanName(data, def.clan)} can train a ${def.name}`);
  const buildingLevel = state.levels[def.building] ?? 0;
  if (buildingLevel < def.requiresLevel) {
    throw new RuleError(`${def.name} needs ${buildingDef(data, def.building).name} level ${def.requiresLevel}`);
  }
  if (state.training.length >= data.units.trainingQueueLimit) throw new RuleError('Training queue is full');

  const cost = unitCost(data, unit, count, villagesOwned);
  const paid = spend(state.ledger, at, cost);
  const last = state.training.at(-1);
  const startsAt = last && batchCompletesAt(last) > at ? batchCompletesAt(last) : at;
  const batch: TrainingBatch = {
    unit,
    count,
    startsAt,
    perUnitMs: perUnitMs(data, unit, buildingLevel, worldSpeed, trainFactor(villageBonuses(data, state), unit)),
  };
  const training = [...state.training, batch];
  const ledger = withRates(paid, at, villageRates(data, { ...state, training }, worldSpeed));
  return { state: { ...state, ledger, training }, batch };
}

// What `count` units cost an owner of `villagesOwned` villages: settlers
// get dearer with every village.
export function unitCost(data: GameData, unit: string, count: number, villagesOwned = 1): Resources {
  const def = data.units.units[unit];
  if (!def) throw new RuleError(`Unknown unit "${unit}"`);
  const factor = (def.costGrowthPerVillage ?? 1) ** Math.max(0, villagesOwned - 1);
  return mapResources((kind) => Math.round(def.cost[kind] * factor) * count);
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
  return { ...next, ledger: withRates(state.ledger, at, villageRates(data, next, worldSpeed)) };
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
  return { ...next, ledger: withRates(state.ledger, at, villageRates(data, next, worldSpeed)) };
}

export function plunder(state: VillageState, loot: Resources, at: Date): VillageState {
  return { ...state, ledger: take(state.ledger, at, loot) };
}
