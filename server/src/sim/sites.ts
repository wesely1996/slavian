// Ancient sites and lore scrolls (PLAN.md §8): where sites lie, who guards
// them, what exploring one finds, and what the group's scrolls give.
// Numbers in data/sites.json and data/lore.json.
import type { GameData, TerrainId } from '../data/index.js';
import { hex, hexDistance, hexKey, type Hex } from './hex.js';
import { mapResources, type Resources } from './resources.js';
import { createRng } from './rng.js';
import { composeWave } from './waves.js';

export interface PlacedSite {
  readonly kind: string;
  readonly q: number;
  readonly r: number;
  readonly guardians: Record<string, number>;
}

export type Find =
  | { readonly type: 'resources'; readonly resources: Resources }
  | { readonly type: 'gear'; readonly item: string }
  | { readonly type: 'ember' }
  | { readonly type: 'scroll'; readonly scroll: string };

function shuffled<T>(items: T[], rng: () => number): T[] {
  const out = [...items];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [out[i], out[j]] = [out[j]!, out[i]!];
  }
  return out;
}

// How far out a hex is, from the Holy City (0) to the edge (1).
export function distanceShare(cell: Hex, radius: number): number {
  return radius > 0 ? Math.min(1, hexDistance(cell, hex(0, 0)) / radius) : 0;
}

export function guardiansFor(data: GameData, cell: Hex, radius: number, seed: number): Record<string, number> {
  const g = data.sites.guardians;
  const size = Math.round(g.baseUnits * (1 + g.distanceGrowth * distanceShare(cell, radius)));
  return composeWave(data, 'north', g.waveIndex, size, seed);
}

// Sites for a new world: mostly in the borderlands, a few mid-map, apart
// from each other and from where players start.
export function placeSites(
  data: GameData,
  input: { terrain: ReadonlyMap<string, TerrainId>; radius: number; startSites: readonly Hex[]; seed: number; players: number },
): PlacedSite[] {
  const p = data.sites.placement;
  const rng = createRng((input.seed ^ 0x51e5) >>> 0);
  const count = Math.max(p.min, p.perPlayer * input.players);
  const midCount = Math.round(count * p.midShare);
  const kinds = Object.entries(data.sites.kinds);
  const usable = [...input.terrain.entries()]
    .map(([key, type]) => {
      const [q, r] = key.split(',').map(Number);
      return { cell: hex(q!, r!), type };
    })
    .filter(({ cell, type }) => {
      if (type === 'holy_city' || data.terrain.terrain[type].moveCost === null) return false;
      if (!kinds.some(([, k]) => k.terrain.includes(type))) return false;
      return input.startSites.every((s) => hexDistance(s, cell) >= p.keepAway);
    })
    .sort((a, b) => a.cell.q - b.cell.q || a.cell.r - b.cell.r);
  const border = usable.filter(({ cell }) => hexDistance(cell, hex(0, 0)) >= input.radius - p.borderBand);
  const mid = usable.filter(({ cell }) => {
    const share = distanceShare(cell, input.radius);
    return share >= p.midRange[0] && share <= p.midRange[1];
  });
  const placed: PlacedSite[] = [];
  const take = (pool: typeof usable, n: number) => {
    let taken = 0;
    for (const { cell, type } of shuffled(pool, rng)) {
      if (taken >= n) break;
      if (placed.some((s) => hexDistance(hex(s.q, s.r), cell) < p.spacing)) continue;
      const fitting = kinds.filter(([, k]) => k.terrain.includes(type)).map(([id]) => id);
      const kind = fitting[Math.floor(rng() * fitting.length)]!;
      const watched = rng() < data.sites.kinds[kind]!.guardianChance;
      placed.push({ kind, q: cell.q, r: cell.r, guardians: watched ? guardiansFor(data, cell, input.radius, (input.seed ^ (placed.length * 0x9e37)) >>> 0) : {} });
      taken++;
    }
  };
  take(mid, midCount);
  take(border, count - midCount);
  return placed;
}

// What exploring a site turns up, seeded by the site: resources (more the
// further out), a piece of gear, an Ember, or a scroll the group lacks.
export function rollFind(
  data: GameData,
  input: { kind: string; seed: number; siteId: number; distance: number; foundScrolls: ReadonlySet<string>; ownedGear: ReadonlySet<string> },
): Find {
  const rng = createRng((input.seed ^ Math.imul(input.siteId + 1, 0x2c1b3c6d) ^ 0xf1d) >>> 0);
  const weights = data.sites.kinds[input.kind]!.finds;
  const scrolls = Object.keys(data.lore.scrolls).filter((s) => !input.foundScrolls.has(s)).sort();
  const gear = Object.keys(data.heroes.items).filter((i) => !input.ownedGear.has(i)).sort();
  const options = (['resources', 'gear', 'scroll', 'ember'] as const).filter(
    (type) => weights[type] > 0 && (type !== 'scroll' || scrolls.length) && (type !== 'gear' || gear.length),
  );
  const total = options.reduce((sum, type) => sum + weights[type], 0);
  let roll = rng() * total;
  const type = options.find((t) => (roll -= weights[t]) < 0) ?? 'resources';
  if (type === 'gear') return { type, item: gear[Math.floor(rng() * gear.length)]! };
  if (type === 'scroll') return { type, scroll: scrolls[Math.floor(rng() * scrolls.length)]! };
  if (type === 'ember') return { type };
  return { type: 'resources', resources: mapResources((kind) => Math.round(data.sites.loot[kind] * (1 + input.distance))) };
}

// What the group's scrolls add to every player's bonuses.
export function loreBonuses(data: GameData, scrolls: Iterable<string>): Record<string, number> {
  const bonuses: Record<string, number> = {};
  for (const scroll of scrolls) {
    for (const [key, value] of Object.entries(data.lore.scrolls[scroll]?.effects ?? {})) bonuses[key] = (bonuses[key] ?? 0) + value;
  }
  return bonuses;
}

export function siteKey(site: { q: number; r: number }): string {
  return hexKey(hex(site.q, site.r));
}
