import type { BuildingDef, GameData } from '../data/index.js';
import { RuleError } from '../errors.js';
import {
  mapResources,
  spend,
  withRates,
  type ResourceLedger,
  type Resources,
} from './resources.js';
import {
  allUnits,
  batchCompletesAt,
  perUnitMs,
  settleTraining,
  upkeepPerHour,
  type TrainingBatch,
  type Units,
} from './training.js';

export interface QueuedBuild {
  readonly building: string;
  readonly targetLevel: number;
  readonly startsAt: Date;
  readonly completesAt: Date;
}

export interface VillageState {
  readonly levels: Readonly<Record<string, number>>;
  readonly ledger: ResourceLedger;
  readonly queue: readonly QueuedBuild[];
  readonly garrison: Units;
  readonly training: readonly TrainingBatch[];
}

const MS_PER_SECOND = 1000;

function buildingDef(data: GameData, building: string): BuildingDef {
  const def = data.buildings.buildings[building];
  if (!def) throw new RuleError(`Unknown building "${building}"`);
  return def;
}

export function levelCost(def: BuildingDef, targetLevel: number): Resources {
  const factor = def.costGrowth ** (targetLevel - 1);
  return mapResources((kind) => Math.round(def.cost[kind] * factor));
}

// Real-time seconds; world speed divides all durations.
export function buildSeconds(def: BuildingDef, targetLevel: number, worldSpeed: number): number {
  return (def.buildSeconds * def.timeGrowth ** (targetLevel - 1)) / worldSpeed;
}

// Real-time rates; world speed multiplies production.
export function productionPerHour(data: GameData, levels: VillageState['levels'], worldSpeed: number): Resources {
  const rates = { ...data.buildings.village.baseProductionPerHour };
  for (const [building, level] of Object.entries(levels)) {
    const production = buildingDef(data, building).production;
    if (!production || level <= 0) continue;
    rates[production.resource] += production.basePerHour * production.growth ** (level - 1);
  }
  return mapResources((kind) => rates[kind] * worldSpeed);
}

// Net rates: production minus grain upkeep for every unit, trained or in
// training. Grain can go negative; the ledger floors amounts at zero.
export function ratesPerHour(data: GameData, levels: VillageState['levels'], units: Units, worldSpeed: number): Resources {
  const rates = productionPerHour(data, levels, worldSpeed);
  return { ...rates, grain: rates.grain - upkeepPerHour(data, units, worldSpeed) };
}

export function capacity(data: GameData, levels: VillageState['levels']): Resources {
  const storehouse = data.buildings.buildings.storehouse;
  const level = levels.storehouse ?? 0;
  const cap = data.buildings.village.baseCapacity * (storehouse?.capacityGrowth ?? 1) ** level;
  return mapResources(() => cap);
}

export function newVillage(data: GameData, at: Date, worldSpeed: number): VillageState {
  const levels = {};
  return {
    levels,
    queue: [],
    garrison: {},
    training: [],
    ledger: {
      amounts: { ...data.buildings.village.startingResources },
      ratesPerHour: productionPerHour(data, levels, worldSpeed),
      capacity: capacity(data, levels),
      settledAt: at,
    },
  };
}

// Level the building will have once everything already queued completes.
function plannedLevel(state: VillageState, building: string): number {
  const queued = state.queue.filter((item) => item.building === building);
  return queued.at(-1)?.targetLevel ?? state.levels[building] ?? 0;
}

// Pays for and queues an upgrade. Builds run one after another, so the new
// item starts when the last queued one completes.
export function queueBuild(
  data: GameData,
  state: VillageState,
  building: string,
  at: Date,
  worldSpeed: number,
): { state: VillageState; queued: QueuedBuild } {
  const def = buildingDef(data, building);
  if (state.queue.length >= data.buildings.village.queueLimit) {
    throw new RuleError('Build queue is full');
  }
  const targetLevel = plannedLevel(state, building) + 1;
  if (targetLevel > def.maxLevel) throw new RuleError(`${def.name} is already at max level`);

  const ledger = spend(state.ledger, at, levelCost(def, targetLevel));
  const startsAt = state.queue.at(-1)?.completesAt ?? at;
  const completesAt = new Date(startsAt.getTime() + buildSeconds(def, targetLevel, worldSpeed) * MS_PER_SECOND);
  const queued: QueuedBuild = { building, targetLevel, startsAt, completesAt };
  return { state: { ...state, ledger, queue: [...state.queue, queued] }, queued };
}

// Applies the head of the queue. `at` is the scheduled completion time, not
// the time the event happens to be processed.
export function completeBuild(
  data: GameData,
  state: VillageState,
  building: string,
  targetLevel: number,
  at: Date,
  worldSpeed: number,
): VillageState {
  const [head, ...rest] = state.queue;
  if (!head || head.building !== building || head.targetLevel !== targetLevel) {
    throw new RuleError(`Build ${building}@${targetLevel} is not at the head of the queue`);
  }
  const levels = { ...state.levels, [building]: targetLevel };
  const units = allUnits(state.garrison, state.training);
  return {
    ...state,
    levels,
    queue: rest,
    ledger: withRates(state.ledger, at, ratesPerHour(data, levels, units, worldSpeed), capacity(data, levels)),
  };
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
  const ledger = withRates(paid, at, ratesPerHour(data, state.levels, allUnits(state.garrison, training), worldSpeed));
  return { state: { ...state, ledger, training }, batch };
}

// Moves units trained by `at` into the garrison. Idempotent.
export function completeTraining(state: VillageState, at: Date): VillageState {
  return { ...state, ...settleTraining(state.garrison, state.training, at) };
}
