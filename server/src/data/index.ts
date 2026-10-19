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
  // A clan's own building: only that clan builds it; its effects add to the
  // village's bonuses per level.
  clan: z.string().optional(),
  effects: z.record(z.string(), z.number()).optional(),
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
  costGrowthPerVillage: z.number().min(1).optional(),
  trainSeconds: z.number().positive(),
  upkeepPerHour: z.number().nonnegative(),
  speed: z.number().positive(),
  attack: z.number().nonnegative(),
  defense: z.number().nonnegative(),
  carry: z.number().nonnegative(),
  // A clan's own unit: only that clan trains it.
  clan: z.string().optional(),
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
  // Only groups of at least this many players see it.
  minPlayers: z.number().int().positive().optional(),
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
      signature: z.string(),
      personality: z.object({
        lootFactor: z.number().nonnegative(),
        raidReach: z.number().int().nonnegative(),
        nerve: z.number().positive(),
        razeBias: z.number(),
        erratic: z.number().min(0).max(1),
      }),
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

const expansionFileSchema = z.object({
  version: z.number().int(),
  settlersNeeded: z.number().int().positive(),
  maxDistance: z.number().int().positive(),
  minVillageDistance: z.number().int().positive(),
  minHolyCityDistance: z.number().int().nonnegative(),
  startingResources: resourcesSchema,
  adminUpkeepPerVillage: z.number().nonnegative(),
  recommendedGarrison: z.object({ base: z.number().int().nonnegative(), perVillage: z.number().int().nonnegative() }),
});

export const RESEARCH_BRANCHES = ['economy', 'military', 'fortification', 'scouting', 'faith'] as const;

const researchFileSchema = z.object({
  version: z.number().int(),
  branches: z.record(z.enum(RESEARCH_BRANCHES), z.string()),
  techs: z.record(
    z.string(),
    z.object({
      name: z.string(),
      branch: z.enum(RESEARCH_BRANCHES),
      academyLevel: z.number().int().positive(),
      requires: z.array(z.string()),
      cost: resourcesSchema,
      seconds: z.number().positive(),
      effects: z.record(z.string(), z.number()),
      description: z.string(),
      // A rare tech: only once the group has found this lore scroll.
      requiresScroll: z.string().optional(),
    }),
  ),
});

export const HERO_SLOTS = ['weapon', 'armor', 'amulet', 'banner', 'mount'] as const;
export type HeroSlot = (typeof HERO_SLOTS)[number];
const effectsSchema = z.record(z.string(), z.number());

const heroesFileSchema = z.object({
  version: z.number().int(),
  speed: z.number().positive(),
  woundHours: z.number().positive(),
  maxLevel: z.number().int().positive(),
  levelXp: z.object({ base: z.number().positive(), growth: z.number().min(1) }),
  dropChance: z.number().min(0).max(1),
  names: z.array(z.string()).min(1),
  branches: z.record(z.string(), z.string()),
  skills: z.record(
    z.string(),
    z.object({
      name: z.string(),
      branch: z.string(),
      maxRank: z.number().int().positive(),
      effectsPerRank: effectsSchema,
      description: z.string(),
    }),
  ),
  slots: z.array(z.enum(HERO_SLOTS)),
  items: z.record(
    z.string(),
    z.object({
      name: z.string(),
      slot: z.enum(HERO_SLOTS),
      effects: effectsSchema,
      set: z.string().optional(),
      description: z.string(),
    }),
  ),
  sets: z.record(z.string(), z.object({ name: z.string(), items: z.array(z.string()).min(2), effects: effectsSchema })),
});

const ordersFileSchema = z.object({
  version: z.number().int(),
  checkMinutes: z.number().positive(),
  maxPerVillage: z.number().int().positive(),
  minSurplus: z.number().nonnegative(),
  surplusShare: z.object({ min: z.number().min(0).max(1), max: z.number().min(0).max(1) }),
});

const notificationsFileSchema = z.object({
  version: z.number().int(),
  waveWarningHours: z.number().positive(),
  bigBuildLevel: z.number().int().positive(),
  pushExpiryHours: z.number().positive(),
});

const armiesFileSchema = z.object({
  version: z.number().int(),
  pincer: z.object({ minAngle: z.number().min(0).max(180), maxBonus: z.number().nonnegative(), scale: z.number().nonnegative() }),
  harass: z.object({
    minCavalryShare: z.number().min(0).max(1),
    maxBonus: z.number().nonnegative(),
    scale: z.number().nonnegative(),
    lossFactor: z.number().min(0).max(1),
  }),
  reinforce: z.object({
    defaultShare: z.number().min(0).max(1),
    defaultRange: z.number().int().nonnegative(),
    maxRange: z.number().int().positive(),
  }),
});

const fieldFileSchema = z.object({
  version: z.number().int(),
  ambush: z.object({ terrain: z.array(z.enum(TERRAIN_IDS)), prepMinutes: z.number().nonnegative(), bonus: z.number().nonnegative() }),
  choke: z.object({
    minBlockedNeighbors: z.number().int().min(1).max(6),
    attackerFactor: z.number().positive().max(1),
    holdTheLineDefense: z.number().nonnegative(),
  }),
  fort: z.object({
    range: z.number().int().positive(),
    cost: resourcesSchema,
    buildSeconds: z.number().positive(),
    defenseBonus: z.number().nonnegative(),
  }),
});

export type BuildingDef = z.infer<typeof buildingSchema>;
export type FieldData = z.infer<typeof fieldFileSchema>;

const hordeFileSchema = z.object({
  version: z.number().int(),
  fear: z.object({
    perDefeat: z.number().nonnegative(),
    perUnitLost: z.number().nonnegative(),
    decayPerWave: z.number().min(0).max(1),
    minimum: z.number().nonnegative(),
    targetWeight: z.number().nonnegative(),
    pathWeight: z.number().nonnegative(),
  }),
  holyCityExtraCost: z.number().nonnegative(),
  rampageHours: z.number().positive(),
  raid: z.object({ recruitShare: z.number().nonnegative() }),
  raze: z.object({
    graceWaves: z.number().int().nonnegative(),
    hours: z.number().positive(),
    minStrength: z.number().positive(),
    threshold: z.number(),
    weakenedPenalty: z.number().nonnegative(),
  }),
  ruins: z.object({ rebuildCostShare: z.number().nonnegative(), rebuildHours: z.number().positive() }),
  refugeeCamp: z.object({ minDistance: z.number().int().positive(), name: z.string() }),
  holyCity: z.object({
    sanctity: z.number().int().positive(),
    guard: z.record(z.string(), z.number().int().nonnegative()),
    guardGrowthPerWave: z.number().min(1),
    stance: z.enum(STANCES),
    damagePerUnit: z.number().nonnegative(),
  }),
});
export type HordeData = z.infer<typeof hordeFileSchema>;

const campsFileSchema = z.object({
  version: z.number().int(),
  spawn: z.object({
    perWave: z.number().int().nonnegative(),
    max: z.number().int().nonnegative(),
    nearRoad: z.number().int().nonnegative(),
    minVillageDistance: z.number().int().nonnegative(),
    baseUnits: z.number().positive(),
    growthPerWave: z.number().min(1),
  }),
  growth: z.object({ everyHours: z.number().positive(), share: z.number().nonnegative(), maxUnits: z.number().int().positive() }),
  feed: z.object({ share: z.number().min(0).max(1) }),
  assault: z.object({ stance: z.enum(STANCES) }),
  loot: z.object({ perUnit: resourcesSchema, gearChance: z.number().min(0).max(1), emberChance: z.number().min(0).max(1) }),
  ambush: z.object({
    reach: z.number().int().nonnegative(),
    escortRatio: z.number().nonnegative(),
    cargoShare: z.number().min(0).max(1),
    escortLoss: z.number().min(0).max(1),
  }),
  fort: z.object({ abandonHours: z.number().positive(), units: z.number().int().positive() }),
});
export type CampsData = z.infer<typeof campsFileSchema>;

export const DIFFICULTIES = ['story', 'normal', 'hard', 'nightmare'] as const;
export type Difficulty = (typeof DIFFICULTIES)[number];
const presetSchema = z.object({
  name: z.string(),
  waveScale: z.number().positive(),
  floor: z.number().positive(),
  maxFactor: z.number().positive(),
  powerWeight: z.number().nonnegative(),
  campRate: z.number().nonnegative(),
  fearWeight: z.number().nonnegative(),
  razeThreshold: z.number(),
  graceWaves: z.number().int().nonnegative(),
});
export type DifficultyPreset = z.infer<typeof presetSchema>;
const difficultyFileSchema = z.object({
  version: z.number().int(),
  default: z.enum(DIFFICULTIES),
  presets: z.record(z.enum(DIFFICULTIES), presetSchema),
  power: z.object({ attackPerPlayer: z.number().positive(), growthPerWave: z.number().nonnegative() }),
});
export type DifficultyData = z.infer<typeof difficultyFileSchema>;

const sitesFileSchema = z.object({
  version: z.number().int(),
  placement: z.object({
    perPlayer: z.number().int().nonnegative(),
    min: z.number().int().nonnegative(),
    borderBand: z.number().int().nonnegative(),
    midShare: z.number().min(0).max(1),
    midRange: z.tuple([z.number().min(0), z.number().max(1)]),
    spacing: z.number().int().positive(),
    keepAway: z.number().int().nonnegative(),
  }),
  kinds: z.record(
    z.string(),
    z.object({
      name: z.string(),
      terrain: z.array(z.enum(TERRAIN_IDS)).min(1),
      exploreHours: z.number().positive(),
      guardianChance: z.number().min(0).max(1),
      finds: z.object({ resources: z.number().nonnegative(), gear: z.number().nonnegative(), scroll: z.number().nonnegative(), ember: z.number().nonnegative() }),
      description: z.string(),
    }),
  ),
  guardians: z.object({ baseUnits: z.number().positive(), distanceGrowth: z.number().nonnegative(), waveIndex: z.number().int().nonnegative() }),
  loot: resourcesSchema,
});
export type SitesData = z.infer<typeof sitesFileSchema>;

const loreFileSchema = z.object({
  version: z.number().int(),
  scrolls: z.record(
    z.string(),
    z.object({ name: z.string(), effects: z.record(z.string(), z.number()), unlocks: z.string().optional(), description: z.string() }),
  ),
});
export type LoreData = z.infer<typeof loreFileSchema>;

const clansFileSchema = z.object({
  version: z.number().int(),
  clans: z.record(
    z.string(),
    z.object({
      name: z.string(),
      animal: z.string(),
      story: z.string(),
      best: z.string(),
      weakness: z.string(),
      effects: z.record(z.string(), z.number()),
      unique: z.union([z.object({ unit: z.string() }), z.object({ building: z.string() })]),
    }),
  ),
});
export type ClansData = z.infer<typeof clansFileSchema>;

export const ONBOARDING_STEPS = ['build', 'train', 'outpost', 'scout', 'camp', 'gift'] as const;
export type OnboardingStep = (typeof ONBOARDING_STEPS)[number];
const onboardingFileSchema = z.object({
  version: z.number().int(),
  steps: z.array(
    z.object({ id: z.enum(ONBOARDING_STEPS), title: z.string(), hint: z.string(), story: z.string(), reward: resourcesSchema }),
  ),
});
export type OnboardingData = z.infer<typeof onboardingFileSchema>;

export const BRIDGE_QUESTS = ['site', 'lair', 'unscathed', 'choke', 'ritual'] as const;
export type BridgeQuest = (typeof BRIDGE_QUESTS)[number];
const bridgeFileSchema = z.object({
  version: z.number().int(),
  story: z.string(),
  buildHours: z.number().positive(),
  powerPerStage: z.number().nonnegative(),
  ritualEmbers: z.number().int().nonnegative(),
  stages: z
    .array(
      z.object({
        name: z.string(),
        // Why the bridge needs this stage, and each quest of it.
        story: z.string(),
        cost: resourcesSchema,
        embers: z.number().int().nonnegative(),
        quests: z.array(z.object({ kind: z.enum(BRIDGE_QUESTS), story: z.string() })),
      }),
    )
    .min(1),
  quests: z.record(z.enum(BRIDGE_QUESTS), z.object({ name: z.string(), description: z.string() })),
  // When the last stage stands: every active front attacks at once, after
  // delayHours (game hours), sizeFactor times its usual strength.
  ritualNight: z.object({
    delayHours: z.number().nonnegative(),
    sizeFactor: z.number().positive(),
    checkHours: z.number().positive(),
    story: z.string(),
  }),
  endings: z.object({
    won: z.object({ title: z.string(), story: z.string() }),
    lost: z.object({ title: z.string(), story: z.string() }),
  }),
});
export type BridgeData = z.infer<typeof bridgeFileSchema>;
export type ArmiesData = z.infer<typeof armiesFileSchema>;
export type NotificationsData = z.infer<typeof notificationsFileSchema>;
export type OrdersData = z.infer<typeof ordersFileSchema>;
export type HeroesData = z.infer<typeof heroesFileSchema>;
export type ResearchData = z.infer<typeof researchFileSchema>;
export type ExpansionData = z.infer<typeof expansionFileSchema>;
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
  expansion: ExpansionData;
  research: ResearchData;
  heroes: HeroesData;
  orders: OrdersData;
  notifications: NotificationsData;
  armies: ArmiesData;
  field: FieldData;
  horde: HordeData;
  camps: CampsData;
  difficulty: DifficultyData;
  sites: SitesData;
  lore: LoreData;
  bridge: BridgeData;
  clans: ClansData;
  onboarding: OnboardingData;
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
    expansion: expansionFileSchema.parse(read('expansion.json')),
    research: researchFileSchema.parse(read('research.json')),
    heroes: heroesFileSchema.parse(read('heroes.json')),
    orders: ordersFileSchema.parse(read('orders.json')),
    notifications: notificationsFileSchema.parse(read('notifications.json')),
    armies: armiesFileSchema.parse(read('armies.json')),
    field: fieldFileSchema.parse(read('field.json')),
    horde: hordeFileSchema.parse(read('horde.json')),
    camps: campsFileSchema.parse(read('camps.json')),
    difficulty: difficultyFileSchema.parse(read('difficulty.json')),
    sites: sitesFileSchema.parse(read('sites.json')),
    lore: loreFileSchema.parse(read('lore.json')),
    bridge: bridgeFileSchema.parse(read('bridge.json')),
    clans: clansFileSchema.parse(read('clans.json')),
    onboarding: onboardingFileSchema.parse(read('onboarding.json')),
  };
  for (const front of data.waves.enabledFronts) {
    if (!data.enemies.fronts[front]) throw new Error(`Front "${front}" is enabled for waves but has no enemies`);
  }
  const { buildings } = data.buildings;
  if (buildings.elder_hall?.kind !== 'center') throw new Error('buildings.json needs a center building "elder_hall"');
  for (const [id, skill] of Object.entries(data.heroes.skills)) {
    if (!data.heroes.branches[skill.branch]) throw new Error(`Hero skill "${id}" is in unknown branch "${skill.branch}"`);
  }
  for (const [id, set] of Object.entries(data.heroes.sets)) {
    for (const item of set.items) if (data.heroes.items[item]?.set !== id) throw new Error(`Set "${id}" lists "${item}"`);
  }
  if (buildings.academy?.kind !== 'center') throw new Error('buildings.json needs a center building "academy"');
  for (const [id, tech] of Object.entries(data.research.techs)) {
    for (const required of tech.requires) {
      if (!data.research.techs[required]) throw new Error(`Tech "${id}" requires unknown tech "${required}"`);
    }
    if (tech.requiresScroll && data.lore.scrolls[tech.requiresScroll]?.unlocks !== id) {
      throw new Error(`Tech "${id}" needs scroll "${tech.requiresScroll}", which doesn't unlock it`);
    }
  }
  for (const [id, scroll] of Object.entries(data.lore.scrolls)) {
    if (scroll.unlocks && data.research.techs[scroll.unlocks]?.requiresScroll !== id) throw new Error(`Scroll "${id}" unlocks "${scroll.unlocks}"`);
  }
  if (data.units.units.settler?.building !== 'settlers_lodge') throw new Error('units.json needs a "settler" trained in the settlers_lodge');
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
    if (unit.clan && !data.clans.clans[unit.clan]) throw new Error(`Unit "${id}" belongs to unknown clan "${unit.clan}"`);
  }
  for (const [id, building] of Object.entries(buildings)) {
    if (building.clan && !data.clans.clans[building.clan]) throw new Error(`Building "${id}" belongs to unknown clan "${building.clan}"`);
  }
  for (const [id, clan] of Object.entries(data.clans.clans)) {
    const unique = 'unit' in clan.unique ? data.units.units[clan.unique.unit] : buildings[clan.unique.building];
    if (unique?.clan !== id) throw new Error(`Clan "${id}" names a unique that isn't its own`);
  }
  return data;
}
