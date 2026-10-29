import type { BuildingDef, GameData, Stance, TerrainId } from '../data/index.js';
import { openTowerSlots, towerIndex, towerPlot, WALL, WALL_PLOT } from './walls.js';
import { clanName, hasClan, villageBonuses } from './clans.js';
import { RuleError } from '../errors.js';
import { hex, hexDistance, hexKey, spiral, type Hex } from './hex.js';
import { bonus, productionFactor, timeFactor, trainFactor, type Bonuses } from './research.js';
import { receive } from './logistics.js';
import {
  mapResources,
  spend,
  take,
  withRates,
  type ResourceKind,
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
// building slots in its center ("c0"…, the first holding the Elder's Hall),
// its walls ("w") and their slots for towers ("t0"…, see walls.ts), and
// outposts on map hexes near it ("o3,-2"). Each plot holds one building
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
export const MARKET = 'market';

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

// A founded village's fields follow the land within outpostRange (the
// outposts' yields say what each terrain gives): one field of every kind,
// the rest shared out by what the land yields (largest remainder, ties in
// the order of the balanced layout). Land that yields nothing keeps the
// balanced layout, as starting villages do.
export function fieldsFromLand(data: GameData, around: readonly (TerrainId | undefined)[]): string[] {
  const balanced = data.buildings.village.fields;
  const kinds = [...new Set(balanced)];
  const yields = data.buildings.buildings.outpost?.yields ?? {};
  const weights = kinds.map((kind) => {
    const resource = data.buildings.buildings[kind]!.production!.resource;
    return around.reduce((sum, t) => sum + (t === undefined ? 0 : (yields[t]?.[resource] ?? 0)), 0);
  });
  const total = weights.reduce((a, b) => a + b, 0);
  const extra = balanced.length - kinds.length;
  if (total === 0 || extra < 0) return [...balanced];
  const counts = weights.map((w) => 1 + Math.floor((w * extra) / total));
  let left = balanced.length - counts.reduce((a, b) => a + b, 0);
  const order = kinds.map((_, i) => i).sort((a, b) => ((weights[b]! * extra) % total) - ((weights[a]! * extra) % total) || a - b);
  for (const i of order) {
    if (left <= 0) break;
    counts[i]! += 1;
    left -= 1;
  }
  return kinds.flatMap((kind, i) => Array<string>(counts[i]!).fill(kind));
}

// The terrain of the hexes around a village's site (not its own).
export function landAround(data: GameData, terrain: ReadonlyMap<string, TerrainId>, cell: Hex): (TerrainId | undefined)[] {
  return spiral(cell, data.buildings.village.outpostRange).slice(1).map((h) => terrain.get(hexKey(h)));
}

export function initialPlots(data: GameData, fields: readonly string[] = data.buildings.village.fields): Record<string, Plot> {
  const { centerSlots } = data.buildings.village;
  const plots: Record<string, Plot> = {};
  fields.forEach((building, i) => (plots[fieldPlot(i)] = { building, level: 0 }));
  for (let i = 0; i < centerSlots; i++) plots[centerPlot(i)] = { building: null, level: 0 };
  plots[HALL_PLOT] = { building: HALL, level: 1 };
  return withWallPlots(data, plots);
}

// A breach knocks the walls down (walls.json breachLevelsLost).
export function breachWalls(data: GameData, state: VillageState): VillageState {
  const wall = state.plots[WALL_PLOT];
  if (!wall || wall.level <= 0) return state;
  const plots = { ...state.plots, [WALL_PLOT]: { ...wall, level: Math.max(0, wall.level - data.walls.breachLevelsLost) } };
  return { ...state, plots, levels: levelsOf(plots) };
}

// The walls (unbuilt) and their slots, for villages laid out before walls.
export function withWallPlots(data: GameData, plots: Plots): Record<string, Plot> {
  const out: Record<string, Plot> = { ...plots };
  out[WALL_PLOT] ??= { building: WALL, level: 0 };
  data.walls.slotsAt.forEach((_, i) => (out[towerPlot(i)] ??= { building: null, level: 0 }));
  return out;
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

// Training batches a village may have waiting: one more for every few
// levels of each military building.
export function trainingQueueLimit(data: GameData, levels: Readonly<Record<string, number>>): number {
  const u = data.units;
  return u.trainingQueueLimit + u.trainingSlotBuildings.reduce((sum, b) => sum + Math.floor((levels[b] ?? 0) / u.buildingLevelsPerTrainingSlot), 0);
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
// feeds: troops at home and in training on garrison rations, units away
// (scouts, settlers, escorts) in full. Field armies carry their own grain.
// Grain can go negative; the ledger floors amounts at zero.
export function villageRates(
  data: GameData,
  state: Pick<VillageState, 'plots' | 'besieged' | 'garrison' | 'training' | 'away' | 'adminUpkeep' | 'bonuses'>,
  worldSpeed: number,
): Resources {
  const bonuses = villageBonuses(data, state);
  const rates = productionPerHour(data, state.plots, worldSpeed, state.besieged, bonuses);
  const home = upkeepPerHour(data, allUnits(state.garrison, state.training), worldSpeed) * data.armies.supply.garrisonUpkeep;
  const troops = (home + upkeepPerHour(data, state.away, worldSpeed)) * Math.max(0, 1 + bonus(bonuses, 'upkeep'));
  const upkeep = troops + state.adminUpkeep * worldSpeed;
  return { ...rates, grain: rates.grain - upkeep };
}

// What the village can keep: every storehouse adds what it holds above the
// base (one storehouse of level n holds base × growth^n).
export function capacity(data: GameData, plots: Plots, bonuses: Bonuses = {}): Resources {
  const growth = data.buildings.buildings.storehouse?.capacityGrowth ?? 1;
  let factor = 1;
  for (const [id, plot] of Object.entries(plots)) {
    if (plot.building === 'storehouse' && plot.level > 0 && !outpostHex(id)) factor += growth ** plot.level - 1;
  }
  const cap = data.buildings.village.baseCapacity * factor * (1 + bonus(bonuses, 'storage'));
  return mapResources(() => cap);
}

// Research the village's Academy brings in per hour (world speed applied).
export function researchPerHour(data: GameData, plots: Plots, worldSpeed: number): number {
  let rate = 0;
  for (const plot of Object.values(plots)) {
    const research = plot.building ? data.buildings.buildings[plot.building]?.research : undefined;
    if (research && plot.level > 0) rate += research.basePerHour * research.growth ** (plot.level - 1) * worldSpeed;
  }
  return rate;
}

// A fresh village. Founded ones (after the first) bring their own
// starting stores and pay administration upkeep.
export function newVillage(
  data: GameData,
  at: Date,
  worldSpeed: number,
  founded: { startingResources: Resources; adminUpkeep: number; bonuses: Bonuses; fields?: readonly string[] } | null = null,
): VillageState {
  const plots = initialPlots(data, founded?.fields);
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
      capacity: capacity(data, plots, state.bonuses),
      settledAt: at,
    },
  };
}

// The owner's research changed: new rates and capacity from `at`.
export function withBonuses(data: GameData, state: VillageState, bonuses: Bonuses, at: Date, worldSpeed: number): VillageState {
  const next = { ...state, bonuses };
  return { ...next, ledger: withRates(state.ledger, at, villageRates(data, next, worldSpeed), capacity(data, state.plots, bonuses)) };
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
  if (def.kind === 'wall') return WALL_PLOT;
  const existing = ids.find((id) => plannedPlot(state, id).building === order.building);
  if (existing) return existing;
  if (def.kind === 'tower') {
    const open = openTowerSlots(data, plannedPlot(state, WALL_PLOT)?.level ?? 0);
    const slot = ids.find((id) => (towerIndex(id) ?? open) < open && plannedPlot(state, id).building === null);
    if (!slot) throw new RuleError('No free wall slot; raise the walls');
    return slot;
  }
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
    const slot = towerIndex(plot);
    if (slot !== null && slot >= openTowerSlots(data, plannedPlot(state, WALL_PLOT)?.level ?? 0)) {
      throw new RuleError('That wall slot is not open yet; raise the walls');
    }
    if (slot === null && !isUnlockedSlot(data, plot, hallLevel)) throw new RuleError('That slot is locked; upgrade the Elder\'s Hall');
    if (!request.building) throw new RuleError('Say which building to construct');
    building = request.building;
    const def = buildingDef(data, building);
    if (slot !== null && def.kind !== 'tower') throw new RuleError(`${def.name} is not built on the walls`);
    if (slot === null && def.kind === 'tower') throw new RuleError(`${def.name} is built in a wall slot`);
    if (slot === null && def.kind !== 'center') throw new RuleError(`${def.name} is built on fields, not in the village`);
    if (def.clan && !hasClan(state.bonuses, def.clan)) throw new RuleError(`Only ${clanName(data, def.clan)} can build a ${def.name}`);
    const taken = !def.multiple && Object.keys(state.plots).some((id) => id !== plot && plannedPlot(state, id).building === building);
    if (taken) throw new RuleError(`This village already has a ${def.name}`);
    const missing = Object.entries(def.requires ?? {}).find(([needed, level]) => (state.levels[needed] ?? 0) < level);
    if (missing) throw new RuleError(`${def.name} needs ${buildingDef(data, missing[0]).name} level ${missing[1]}`);
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
  return { ...next, ledger: withRates(state.ledger, at, villageRates(data, next, worldSpeed), capacity(data, plots, state.bonuses)) };
}

// Everything a building of `level` cost to raise, level by level.
export function builtCost(def: BuildingDef, level: number): Resources {
  const sum = mapResources(() => 0);
  for (let l = 1; l <= level; l++) {
    const cost = levelCost(def, l);
    for (const kind of Object.keys(sum) as (keyof Resources)[]) sum[kind] += cost[kind];
  }
  return sum;
}

// What tearing down everything that stands on `plots` gives back.
export function refundOf(data: GameData, plots: Plots, share: number): Resources {
  const sum = mapResources(() => 0);
  for (const plot of Object.values(plots)) {
    const def = plot.building ? data.buildings.buildings[plot.building] : undefined;
    if (!def || plot.level <= 0) continue;
    const cost = builtCost(def, plot.level);
    for (const kind of Object.keys(sum) as (keyof Resources)[]) sum[kind] += cost[kind];
  }
  return mapResources((kind) => Math.floor(sum[kind] * share));
}

// Tears down the building on a center or wall slot: the slot is free again
// and the village gets back a share of what it cost (what fits its stores).
export function demolish(data: GameData, state: VillageState, plot: string, at: Date, worldSpeed: number): { state: VillageState; refund: Resources } {
  const current = state.plots[plot];
  if (!current?.building || current.level <= 0) throw new RuleError('Nothing stands there to tear down');
  const def = buildingDef(data, current.building);
  if (current.building === HALL) throw new RuleError("The Elder's Hall can't be torn down");
  if (def.kind !== 'center' && def.kind !== 'tower') throw new RuleError(`The ${def.name} can't be torn down`);
  if (state.queue.some((item) => item.plot === plot)) throw new RuleError(`The ${def.name} is being built; wait for it to finish`);
  const refund = refundOf(data, { [plot]: current }, data.buildings.village.demolishRefund);
  const plots = { ...state.plots, [plot]: { building: null, level: 0 } };
  const levels = levelsOf(plots);
  const next = { ...state, plots, levels };
  const ledger = withRates(state.ledger, at, villageRates(data, next, worldSpeed), capacity(data, plots, state.bonuses));
  return { state: { ...next, ledger: receive(ledger, at, refund).ledger }, refund };
}

// What one resource fetches of another at the village's Market.
export function marketRate(data: GameData, marketLevel: number): number {
  const { baseRate, ratePerLevel } = data.buildings.village.market;
  return marketLevel > 0 ? baseRate + ratePerLevel * (marketLevel - 1) : 0;
}

// Trades `amount` of `give` for `get` at the Market: what is bought goes
// into the stores, as far as they hold.
export function trade(
  data: GameData,
  state: VillageState,
  order: { give: ResourceKind; get: ResourceKind; amount: number },
  at: Date,
): { state: VillageState; got: number } {
  const rate = marketRate(data, state.levels[MARKET] ?? 0);
  if (rate <= 0) throw new RuleError('Build a Market to trade');
  if (order.give === order.get) throw new RuleError('Trade one resource for another');
  if (!Number.isInteger(order.amount) || order.amount < 1) throw new RuleError('Trade at least 1');
  const got = Math.floor(order.amount * rate);
  if (got < 1) throw new RuleError('Too little to fetch anything');
  const paid = spend(state.ledger, at, mapResources((kind) => (kind === order.give ? order.amount : 0)));
  const ledger = receive(paid, at, mapResources((kind) => (kind === order.get ? got : 0))).ledger;
  return { state: { ...state, ledger }, got };
}

// The Market buys a piece of spare gear: its price goes into the stores.
export function sellGear(data: GameData, state: VillageState, at: Date): VillageState {
  if ((state.levels[MARKET] ?? 0) <= 0) throw new RuleError('Build a Market to sell gear');
  return { ...state, ledger: receive(state.ledger, at, data.buildings.village.market.gearValue).ledger };
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
  if (state.training.length >= trainingQueueLimit(data, state.levels)) throw new RuleError('Training queue is full');

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

// Sends `count` units of `unit` away from home (they eat full rations
// away). Units finished training by `at` count as home.
export function sendAway(data: GameData, state: VillageState, unit: string, count: number, at: Date, worldSpeed: number): VillageState {
  const settled = completeTraining(state, at);
  const home = settled.garrison[unit] ?? 0;
  if (home < count) throw new NotEnoughUnitsError(`Only ${home} ${unit} at home`);
  const next = { ...settled, garrison: { ...settled.garrison, [unit]: home - count }, away: addUnits(settled.away, { [unit]: count }) };
  return { ...next, ledger: withRates(settled.ledger, at, villageRates(data, next, worldSpeed), settled.ledger.capacity) };
}

// Units leaving the garrison for good, or as a field army (which carries
// its own grain). Units finished training by `at` count as home.
export function leaveGarrison(data: GameData, state: VillageState, units: Units, at: Date, worldSpeed: number): VillageState {
  const settled = completeTraining(state, at);
  const garrison: Record<string, number> = { ...settled.garrison };
  for (const [unit, count] of Object.entries(units)) {
    const home = garrison[unit] ?? 0;
    if (home < count) throw new NotEnoughUnitsError(`Only ${home} ${unit} at home`);
    garrison[unit] = home - count;
  }
  const next = { ...settled, garrison };
  return { ...next, ledger: withRates(settled.ledger, at, villageRates(data, next, worldSpeed), settled.ledger.capacity) };
}

// Units away that will never come back (killed): they stop eating now.
export function loseAway(data: GameData, state: VillageState, unit: string, count: number, at: Date, worldSpeed: number): VillageState {
  const away = { ...state.away, [unit]: Math.max(0, (state.away[unit] ?? 0) - count) };
  const next = { ...state, away };
  return { ...next, ledger: withRates(state.ledger, at, villageRates(data, next, worldSpeed)) };
}

// Units coming home from a mission, back on garrison rations.
export function returnHome(data: GameData, state: VillageState, unit: string, count: number, at: Date, worldSpeed: number): VillageState {
  const next = {
    ...state,
    away: { ...state.away, [unit]: Math.max(0, (state.away[unit] ?? 0) - count) },
    garrison: addUnits(state.garrison, { [unit]: count }),
  };
  return { ...next, ledger: withRates(state.ledger, at, villageRates(data, next, worldSpeed), state.ledger.capacity) };
}

// Garrison losses in battle: the dead stop eating from `at`.
export function loseGarrison(data: GameData, state: VillageState, losses: Units, at: Date, worldSpeed: number): VillageState {
  const garrison: Record<string, number> = { ...state.garrison };
  for (const [unit, count] of Object.entries(losses)) garrison[unit] = Math.max(0, (garrison[unit] ?? 0) - count);
  const next = { ...state, garrison };
  return { ...next, ledger: withRates(state.ledger, at, villageRates(data, next, worldSpeed)) };
}

// Of the garrison's fallen (`lost`), those its hospital saves: each gets up
// again with the hospital's chance, drawn from `rng` unit by unit (by name).
export function hospitalHealed(bonuses: Bonuses, lost: Units, rng: () => number): Record<string, number> {
  const chance = Math.min(1, bonus(bonuses, 'hospital'));
  const healed: Record<string, number> = {};
  if (chance <= 0) return healed;
  for (const unit of Object.keys(lost).sort()) {
    let saved = 0;
    for (let i = 0; i < lost[unit]!; i++) if (rng() < chance) saved++;
    if (saved > 0) healed[unit] = saved;
  }
  return healed;
}

// Soldiers joining the garrison (back on their feet, or moved in): home,
// eating from `at`.
export function joinGarrison(data: GameData, state: VillageState, healed: Units, at: Date, worldSpeed: number): VillageState {
  const next = { ...state, garrison: addUnits(state.garrison, healed) };
  return { ...next, ledger: withRates(state.ledger, at, villageRates(data, next, worldSpeed), state.ledger.capacity) };
}

export function plunder(state: VillageState, loot: Resources, at: Date): VillageState {
  return { ...state, ledger: take(state.ledger, at, loot) };
}
