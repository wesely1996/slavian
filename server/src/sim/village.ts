import type { BuildingDef, GameData } from '../data/index.js';
import { RuleError } from '../errors.js';
import {
  mapResources,
  spend,
  withRates,
  type ResourceLedger,
  type Resources,
} from './resources.js';

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
  return {
    levels,
    queue: rest,
    ledger: withRates(state.ledger, at, productionPerHour(data, levels, worldSpeed), capacity(data, levels)),
  };
}
