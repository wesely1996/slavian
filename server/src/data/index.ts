import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { z } from 'zod';
import { FRONTS } from '../sim/mapgen.js';
import { RESOURCE_KINDS } from '../sim/resources.js';

// Shared game data lives in /data at the repository root.
export const DATA_DIR = fileURLToPath(new URL('../../../data/', import.meta.url));

export const TERRAIN_IDS = [
  'plains',
  'forest',
  'hills',
  'mountain',
  'swamp',
  'lake',
  'holy_city',
  'ocean',
  'dark_forest',
  'ice',
  'steppe',
  'hallowed',
] as const;
export type TerrainId = (typeof TERRAIN_IDS)[number];

const resourcesSchema = z.object({
  wood: z.number().nonnegative(),
  stone: z.number().nonnegative(),
  grain: z.number().nonnegative(),
  iron: z.number().nonnegative(),
});

const buildingSchema = z.object({
  name: z.string(),
  // 'field': a resource plot around the village; 'center': a building slot;
  // 'outpost': built on a resource hex near the village.
  kind: z.enum(['field', 'center', 'outpost']),
  maxLevel: z.number().int().positive(),
  cost: resourcesSchema,
  costGrowth: z.number().min(1),
  buildSeconds: z.number().positive(),
  timeGrowth: z.number().min(1),
  production: z
    .object({
      resource: z.enum(RESOURCE_KINDS),
      basePerHour: z.number().positive(),
      growth: z.number().min(1),
    })
    .optional(),
  capacityGrowth: z.number().min(1).optional(),
  // Outposts: resources per hour at level 1, by the terrain they stand on.
  yields: z.partialRecord(z.enum(TERRAIN_IDS), resourcesSchema.partial()).optional(),
  yieldGrowth: z.number().min(1).optional(),
});

const buildingsFileSchema = z.object({
  version: z.number().int(),
  village: z.object({
    startingResources: resourcesSchema,
    baseProductionPerHour: resourcesSchema,
    baseCapacity: z.number().positive(),
    fields: z.array(z.string()).min(1),
    centerSlots: z.number().int().positive(),
    slotsUnlockedAtStart: z.number().int().positive(),
    slotsPerHallLevel: z.number().int().nonnegative(),
    baseQueueLimit: z.number().int().positive(),
    hallLevelsPerQueueSlot: z.number().int().positive(),
    hallBuildSpeedup: z.number().positive().max(1),
    outpostRange: z.number().int().positive(),
    baseOutposts: z.number().int().nonnegative(),
    hallLevelsPerOutpost: z.number().int().positive(),
  }),
  buildings: z.record(z.string(), buildingSchema),
});


const terrainSchema = z.object({
  name: z.string(),
  moveCost: z.number().positive().nullable(),
  settleable: z.boolean(),
  edge: z.boolean(),
});

const terrainFileSchema = z.object({
  version: z.number().int(),
  terrain: z.record(z.enum(TERRAIN_IDS), terrainSchema),
});

export const UNIT_FAMILIES = ['infantry', 'archers', 'cavalry', 'scout'] as const;
export type UnitFamily = (typeof UNIT_FAMILIES)[number];
export const STANCES = ['defensive', 'balanced', 'offensive', 'hold_the_line'] as const;
export type Stance = (typeof STANCES)[number];

const unitSchema = z.object({
  name: z.string(),
  family: z.enum(UNIT_FAMILIES),
  building: z.string(),
  requiresLevel: z.number().int().positive(),
  cost: resourcesSchema,
  trainSeconds: z.number().positive(),
  upkeepPerHour: z.number().nonnegative(),
  speed: z.number().positive(),
  attack: z.number().nonnegative(),
  defense: z.number().nonnegative(),
  carry: z.number().nonnegative(),
});

const unitsFileSchema = z.object({
  version: z.number().int(),
  trainingQueueLimit: z.number().int().positive(),
  maxBatch: z.number().int().positive(),
  trainingSpeedup: z.number().positive().max(1),
  units: z.record(z.string(), unitSchema),
});

const enemyUnitSchema = z.object({
  name: z.string(),
  family: z.enum(UNIT_FAMILIES),
  weight: z.number().positive(),
  minWave: z.number().int().nonnegative(),
  attack: z.number().nonnegative(),
  defense: z.number().nonnegative(),
  speed: z.number().positive(),
});

const enemiesFileSchema = z.object({
  version: z.number().int(),
  fronts: z.partialRecord(
    z.enum(FRONTS),
    z.object({
      faction: z.string(),
      spawnTerrain: z.array(z.enum(TERRAIN_IDS)).min(1),
      units: z.record(z.string(), enemyUnitSchema),
      stances: z.partialRecord(z.enum(STANCES), z.number().positive()),
    }),
  ),
});

const wavesFileSchema = z.object({
  version: z.number().int(),
  enabledFronts: z.array(z.enum(FRONTS)).min(1),
  graceHours: z.number().nonnegative(),
  intervalHours: z.tuple([z.number().positive(), z.number().positive()]),
  upcoming: z.number().int().positive(),
  rampageHours: z.number().positive(),
  raidReach: z.number().int().nonnegative(),
  baseUnits: z.number().positive(),
  growthPerWave: z.number().min(1),
  perExtraPlayer: z.number().nonnegative(),
  threatLevels: z.array(z.object({ name: z.string(), maxUnits: z.number().int().positive().nullable() })).min(1),
});

const scoutingFileSchema = z.object({
  version: z.number().int(),
  survival: z.partialRecord(z.enum(FRONTS), z.number().min(0).max(1)),
  defaultSurvival: z.number().min(0).max(1),
  maxScouts: z.number().int().positive(),
  tiers: z
    .array(
      z.object({
        name: z.string(),
        minSurvivors: z.number().int().positive(),
        sizeError: z.number().min(0),
        unitError: z.number().min(0).nullable(),
        revealsStance: z.boolean(),
      }),
    )
    .min(1),
});

const familyMultipliers = z.partialRecord(z.enum(UNIT_FAMILIES), z.number().positive());
const stanceMultipliers = z.partialRecord(z.enum(STANCES), z.number().positive());

const battleFileSchema = z.object({
  version: z.number().int(),
  roundMinutes: z.number().positive(),
  maxRounds: z.number().int().positive(),
  casualtyScale: z.number().positive(),
  homeBonus: z.number().positive(),
  variance: z.number().min(0).max(1),
  raidShare: z.number().min(0).max(1),
  counters: z.partialRecord(z.enum(UNIT_FAMILIES), familyMultipliers),
  stances: z.record(
    z.enum(STANCES),
    z.object({
      name: z.string(),
      attack: z.number().positive(),
      defense: z.number().positive(),
      retreatAt: z.number().positive().max(1).nullable(),
    }),
  ),
  matchups: z.partialRecord(z.enum(STANCES), stanceMultipliers),
});

const logisticsFileSchema = z.object({
  version: z.number().int(),
  caravan: z.object({
    capacity: z.number().int().positive(),
    speed: z.number().positive(),
    caravansPerYardLevel: z.number().int().positive(),
  }),
  vault: z.object({
    baseCapacity: z.number().positive(),
    capacityGrowth: z.number().min(1),
    maxLevel: z.number().int().positive(),
    upgradeCost: resourcesSchema,
    costGrowth: z.number().min(1),
    upgradeSeconds: z.number().positive(),
    timeGrowth: z.number().min(1),
  }),
});

export type BuildingDef = z.infer<typeof buildingSchema>;
export type LogisticsData = z.infer<typeof logisticsFileSchema>;
export type BattleData = z.infer<typeof battleFileSchema>;
export type ScoutingData = z.infer<typeof scoutingFileSchema>;
export type EnemiesData = z.infer<typeof enemiesFileSchema>;
export type WavesData = z.infer<typeof wavesFileSchema>;
export type UnitDef = z.infer<typeof unitSchema>;
export type UnitsData = z.infer<typeof unitsFileSchema>;
export type BuildingsData = z.infer<typeof buildingsFileSchema>;
export type TerrainDef = z.infer<typeof terrainSchema>;
export type TerrainData = z.infer<typeof terrainFileSchema>;

export interface GameData {
  buildings: BuildingsData;
  terrain: TerrainData;
  units: UnitsData;
  enemies: EnemiesData;
  waves: WavesData;
  scouting: ScoutingData;
  battle: BattleData;
  logistics: LogisticsData;
}

export function loadGameData(dir: string = DATA_DIR): GameData {
  const read = (file: string): unknown => JSON.parse(readFileSync(`${dir}/${file}`, 'utf8'));
  const data: GameData = {
    buildings: buildingsFileSchema.parse(read('buildings.json')),
    terrain: terrainFileSchema.parse(read('terrain.json')),
    units: unitsFileSchema.parse(read('units.json')),
    enemies: enemiesFileSchema.parse(read('enemies.json')),
    waves: wavesFileSchema.parse(read('waves.json')),
    scouting: scoutingFileSchema.parse(read('scouting.json')),
    battle: battleFileSchema.parse(read('battle.json')),
    logistics: logisticsFileSchema.parse(read('logistics.json')),
  };
  for (const front of data.waves.enabledFronts) {
    if (!data.enemies.fronts[front]) throw new Error(`Front "${front}" is enabled for waves but has no enemies`);
  }
  const { buildings } = data.buildings;
  if (buildings.elder_hall?.kind !== 'center') throw new Error('buildings.json needs a center building "elder_hall"');
  if (buildings.caravan_yard?.kind !== 'center') throw new Error('buildings.json needs a center building "caravan_yard"');
  if (buildings.outpost?.kind !== 'outpost' || !buildings.outpost.yields) {
    throw new Error('buildings.json needs an outpost building "outpost" with yields');
  }
  for (const field of data.buildings.village.fields) {
    if (buildings[field]?.kind !== 'field') throw new Error(`Village field "${field}" is not a field building`);
  }
  for (const [id, unit] of Object.entries(data.units.units)) {
    if (!data.buildings.buildings[unit.building]) {
      throw new Error(`Unit "${id}" is trained in unknown building "${unit.building}"`);
    }
  }
  return data;
}
