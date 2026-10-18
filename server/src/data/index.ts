import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { z } from 'zod';
import { RESOURCE_KINDS } from '../sim/resources.js';

// Shared game data lives in /data at the repository root.
export const DATA_DIR = fileURLToPath(new URL('../../../data/', import.meta.url));

const resourcesSchema = z.object({
  wood: z.number().nonnegative(),
  stone: z.number().nonnegative(),
  grain: z.number().nonnegative(),
  iron: z.number().nonnegative(),
});

const buildingSchema = z.object({
  name: z.string(),
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
});

const buildingsFileSchema = z.object({
  version: z.number().int(),
  village: z.object({
    startingResources: resourcesSchema,
    baseProductionPerHour: resourcesSchema,
    baseCapacity: z.number().positive(),
    queueLimit: z.number().int().positive(),
  }),
  buildings: z.record(z.string(), buildingSchema),
});

export type BuildingDef = z.infer<typeof buildingSchema>;
export type BuildingsData = z.infer<typeof buildingsFileSchema>;

export interface GameData {
  buildings: BuildingsData;
}

export function loadGameData(dir: string = DATA_DIR): GameData {
  const read = (file: string): unknown => JSON.parse(readFileSync(`${dir}/${file}`, 'utf8'));
  return {
    buildings: buildingsFileSchema.parse(read('buildings.json')),
  };
}
