// The ground a battle is fought on (battle.json terrain): what its hex
// counts as (terrain.json ground), how many mountains stand beside it and
// how many waters (rivers along it, lakes beside it). Each feature adds its
// share to the attack or defense of the units that fight there: their
// family's, their own (units.json terrain) and their clan's.
import type { GameData, GroundFeature, TerrainId } from '../data/index.js';
import { hexKey, neighbors, type Hex } from './hex.js';
import { edgeKey } from './land.js';
import { bonus, type Bonuses } from './research.js';

// How much of each feature the hex has: 1 for its own ground, the number of
// mountains or waters around it.
export type Ground = Readonly<Partial<Record<GroundFeature, number>>>;

export type TerrainShares = Readonly<Partial<Record<GroundFeature, { readonly attack?: number | undefined; readonly defense?: number | undefined }>>>;

const SHARE_KEY = /^terrain\.(\w+)\.(attack|defense)$/;

// The ground at `cell`: `terrain` the world's hexes, `rivers` the keys
// (edgeKey) of every river edge, bridged or not.
export function groundAt(data: GameData, terrain: ReadonlyMap<string, TerrainId>, rivers: ReadonlySet<string>, cell: Hex): Ground {
  const own = terrain.get(hexKey(cell));
  const out: Partial<Record<GroundFeature, number>> = {};
  for (const tag of (own ? data.terrain.terrain[own]?.ground : undefined) ?? []) out[tag] = 1;
  let mountains = 0;
  let waters = 0;
  for (const n of neighbors(cell)) {
    const t = terrain.get(hexKey(n));
    if (t === 'mountain') mountains++;
    if (t === 'lake') waters++;
    if (rivers.has(edgeKey(cell, n))) waters++;
  }
  if (mountains > 0) out.mountain = mountains;
  if (waters > 0) out.water = waters;
  return out;
}

// A player's terrain shares from their bonuses (terrain.<feature>.<stat>:
// their clan's) on top of the unit's own.
export function playerShares(own: TerrainShares | undefined, bonuses: Bonuses): TerrainShares | undefined {
  let out: Partial<Record<GroundFeature, { attack?: number; defense?: number }>> | undefined;
  for (const key of Object.keys(bonuses)) {
    const m = SHARE_KEY.exec(key);
    if (!m) continue;
    out ??= structuredClone({ ...(own ?? {}) }) as Partial<Record<GroundFeature, { attack?: number; defense?: number }>>;
    const feature = m[1] as GroundFeature;
    const stat = m[2] as 'attack' | 'defense';
    const now = { ...(out[feature] ?? {}) };
    now[stat] = (now[stat] ?? 0) + bonus(bonuses, key);
    out[feature] = now;
  }
  return out ?? own;
}

// What `ground` makes of a unit of `family` with its own `shares`: its
// attack and defense factors (the shares of every feature there, each
// counted up to maxStack times, added up).
export function groundFactors(data: GameData, ground: Ground | undefined, family: string, shares: TerrainShares | undefined): { attack: number; defense: number } {
  if (!ground) return { attack: 1, defense: 1 };
  const { maxStack, families } = data.battle.terrain;
  const familyShares = (families as Record<string, TerrainShares | undefined>)[family];
  let attack = 0;
  let defense = 0;
  for (const [feature, count] of Object.entries(ground) as [GroundFeature, number][]) {
    if (!count) continue;
    const times = Math.min(count, maxStack);
    for (const s of [familyShares?.[feature], shares?.[feature]]) {
      attack += (s?.attack ?? 0) * times;
      defense += (s?.defense ?? 0) * times;
    }
  }
  return { attack: Math.max(0, 1 + attack), defense: Math.max(0, 1 + defense) };
}
