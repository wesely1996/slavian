// Daily map events (data/events.json): each game day after the first, one
// rises near one of the players' villages: captives held in a camp, or a
// hard ruin.
import type { GameData, TerrainId } from '../data/index.js';
import type { CampReward } from '../db/camps.js';
import { hexDistance, hexKey, ring, type Hex } from './hex.js';
import { frontOf, type Front } from './mapgen.js';
import { mapResources } from './resources.js';
import { createRng } from './rng.js';
import { guardiansFor, type PlacedSite } from './sites.js';
import { composeWave, type Composition } from './waves.js';

export type MapEventPlan =
  | { kind: 'captives'; cell: Hex; front: Front; guards: Composition; reward: CampReward }
  | { kind: 'ruin'; cell: Hex; site: PlacedSite };

// The event of `day` (1: the first, a game day into the run), or null when
// there is nowhere to put it.
export function planMapEvent(
  data: GameData,
  input: {
    terrain: ReadonlyMap<string, TerrainId>;
    radius: number;
    // The players' villages (by id), the hexes taken and the sites standing.
    villages: readonly Hex[];
    taken: ReadonlySet<string>;
    sites: readonly Hex[];
    activeFronts: readonly Front[];
    seed: number;
    day: number;
    players: number;
  },
): MapEventPlan | null {
  const rules = data.events;
  const rng = createRng((input.seed ^ Math.imul(input.day + 1, 0x632be5ab)) >>> 0);
  if (input.villages.length === 0) return null;
  const { captives, ruin } = rules.kinds;
  const kind: 'captives' | 'ruin' = rng() * (captives.weight + ruin.weight) < captives.weight ? 'captives' : 'ruin';
  const center = input.villages[Math.floor(rng() * input.villages.length)]!;
  const usable: { cell: Hex; type: TerrainId }[] = [];
  for (let d = rules.range.min; d <= rules.range.max; d++) {
    for (const cell of ring(center, d)) {
      const type = input.terrain.get(hexKey(cell));
      if (!type || type === 'holy_city' || data.terrain.terrain[type].moveCost === null || input.taken.has(hexKey(cell))) continue;
      if (kind === 'ruin' && !Object.values(data.sites.kinds).some((k) => k.terrain.includes(type))) continue;
      if (kind === 'ruin' && input.sites.some((s) => hexDistance(s, cell) < 2)) continue;
      usable.push({ cell, type });
    }
  }
  if (usable.length === 0) return null;
  const { cell, type } = usable[Math.floor(rng() * usable.length)]!;
  const grown = 1 + captives.growthPerDay * (input.day - 1);
  if (kind === 'captives') {
    const own = frontOf(cell);
    const front = input.activeFronts.includes(own) ? own : input.activeFronts[0]!;
    const guards = composeWave(data, front, input.day, Math.round(captives.guards * grown), (input.seed ^ input.day) >>> 0, input.players);
    const reward: CampReward =
      rng() < captives.unitsChance
        ? { units: { [captives.units[Math.floor(rng() * captives.units.length)]!]: captives.count + Math.floor(captives.countPerDay * (input.day - 1)) } }
        : { resources: mapResources((k) => Math.round(captives.resources[k] * grown)) };
    return { kind, cell, front, guards, reward };
  }
  const fitting = Object.entries(data.sites.kinds)
    .filter(([, k]) => k.terrain.includes(type))
    .map(([id]) => id);
  const siteKind = fitting[Math.floor(rng() * fitting.length)]!;
  const guardians: Composition = {};
  for (const [unit, n] of Object.entries(guardiansFor(data, cell, input.radius, (input.seed ^ Math.imul(input.day, 0x9e37)) >>> 0))) {
    guardians[unit] = Math.round(n * ruin.guardianFactor);
  }
  return { kind, cell, site: { kind: siteKind, q: cell.q, r: cell.r, guardians } };
}
