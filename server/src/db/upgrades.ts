// Data upgrades that need game rules, run on server start after the SQL
// migrations. Each is idempotent.
import type { GameData } from '../data/index.js';
import { HALL_PLOT, levelsOf, plotsFromLegacyLevels, withBonuses, withWallPlots, type Plot } from '../sim/village.js';
import { loadVillage, saveVillageState } from './villages.js';
import { WALL_PLOT } from '../sim/walls.js';
import { ensureDigests } from '../scheduler/notices.js';
import { ensureMapEvents } from '../scheduler/mapEvents.js';
import { ensurePrune } from '../scheduler/prune.js';
import { ensureSites } from '../scheduler/sites.js';
import { assignHeroKinds, ensureHeroes } from './heroes.js';
import { refreshBonuses } from '../scheduler/research.js';
import { getWorld } from './worlds.js';
import { inTransaction, type Db } from './pool.js';
import { isDefaultName, townName } from '../sim/names.js';
import { createRng } from '../sim/rng.js';
import { ruinStorage } from '../sim/horde.js';
import { RESOURCE_KINDS, type Resources } from '../sim/resources.js';

interface LegacyRow {
  id: number;
  levels: Record<string, number>;
  queue: { plot?: string; building: string; targetLevel: number }[];
}

// Villages from before plots existed: lay out their buildings on plots and
// give queued builds a plot (new constructions take the next free slot).
export async function upgradeLegacyVillages(db: Db, data: GameData): Promise<number> {
  return inTransaction(db, async (client) => {
    const { rows } = await client.query<LegacyRow>('SELECT id, levels, queue FROM villages WHERE plots IS NULL FOR UPDATE');
    for (const row of rows) {
      const plots: Record<string, Plot> = plotsFromLegacyLevels(data, row.levels);
      const reserved = new Map<string, string>();
      const queue = row.queue.map((item) => {
        if (item.plot) return item;
        const kind = data.buildings.buildings[item.building]?.kind;
        let plot = Object.keys(plots).find((id) => plots[id]!.building === item.building) ?? reserved.get(item.building);
        if (!plot && kind === 'center') {
          plot = Object.keys(plots).find(
            (id) => id !== HALL_PLOT && id.startsWith('c') && plots[id]!.building === null && ![...reserved.values()].includes(id),
          );
          if (plot) reserved.set(item.building, plot);
        }
        return { ...item, plot: plot ?? '' };
      });
      await client.query('UPDATE villages SET plots = $2, queue = $3 WHERE id = $1', [
        row.id,
        JSON.stringify(plots),
        JSON.stringify(queue),
      ]);
    }
    return rows.length;
  });
}

// Villages laid out before walls: add the walls (unbuilt) and their slots.
export async function upgradeWallPlots(db: Db, data: GameData): Promise<number> {
  return inTransaction(db, async (client) => {
    const { rows } = await client.query<{ id: number; plots: Record<string, Plot> }>(
      'SELECT id, plots FROM villages WHERE plots IS NOT NULL AND NOT plots ? $1 FOR UPDATE',
      [WALL_PLOT],
    );
    for (const row of rows) {
      await client.query('UPDATE villages SET plots = $2 WHERE id = $1', [row.id, JSON.stringify(withWallPlots(data, row.plots))]);
    }
    return rows.length;
  });
}

// Worlds started before heroes existed: give every player theirs.
export async function upgradeHeroes(db: Db, data: GameData): Promise<number> {
  return inTransaction(db, async (client) => {
    const { rows } = await client.query<{ id: number; seed: number; status: string }>(`SELECT id, seed, status FROM worlds WHERE status <> 'lobby'`);
    let created = 0;
    for (const world of rows) {
      // Runs from before the roster: each player gets a roster hero, whose
      // strengths and traits reach their villages.
      const assigned = await assignHeroKinds(client, data, world.id);
      if (assigned.length && world.status === 'running') await refreshBonuses(client, data, await getWorld(client, world.id), assigned, new Date());
      created += await ensureHeroes(client, data, world.id);
    }
    return created;
  });
}

// Worlds started before the daily digest: schedule everyone's.
export async function upgradeDigests(db: Db, now: Date): Promise<void> {
  await inTransaction(db, async (client) => {
    const { rows } = await client.query<{ id: number }>(`SELECT id FROM worlds WHERE status <> 'lobby'`);
    for (const { id } of rows) await ensureDigests(client, await getWorld(client, id), now);
  });
}

// Running worlds started before daily map events: the next day's planned.
export async function upgradeMapEvents(db: Db, data: GameData, now: Date): Promise<void> {
  await inTransaction(db, async (client) => {
    const { rows } = await client.query<{ id: number }>(`SELECT id FROM worlds WHERE status = 'running'`);
    for (const { id } of rows) {
      const world = await getWorld(client, id);
      await ensureMapEvents(client, data, world, now);
      // And daily pruning.
      await ensurePrune(client, world, now);
    }
  });
}

// Worlds started before ancient sites existed get theirs.
export async function upgradeSites(db: Db, data: GameData): Promise<number> {
  return inTransaction(db, async (client) => {
    const { rows } = await client.query<{ id: number }>(
      `SELECT id FROM worlds w WHERE status = 'running' AND NOT EXISTS (SELECT 1 FROM sites s WHERE s.world_id = w.id)`,
    );
    for (const { id } of rows) await ensureSites(client, data, await getWorld(client, id));
    return rows.length;
  });
}

// Towns named the old way ("Mila's village 2"): give each a town name of its
// own, unique in its world.
export async function upgradeTownNames(db: Db, data: GameData): Promise<number> {
  return inTransaction(db, async (client) => {
    const { rows } = await client.query<{ id: number; world_id: number; name: string; seed: number }>(
      'SELECT v.id, v.world_id, v.name, w.seed FROM villages v JOIN worlds w ON w.id = v.world_id ORDER BY v.world_id, v.id FOR UPDATE OF v',
    );
    let renamed = 0;
    for (const worldId of new Set(rows.map((r) => r.world_id))) {
      const towns = rows.filter((r) => r.world_id === worldId);
      const taken = towns.filter((t) => !isDefaultName(t.name)).map((t) => t.name);
      const rng = createRng((towns[0]!.seed ^ 0x7a11) >>> 0);
      for (const town of towns.filter((t) => isDefaultName(t.name))) {
        const name = townName(data, taken, rng);
        taken.push(name);
        await client.query('UPDATE villages SET name = $2 WHERE id = $1', [town.id, name]);
        renamed++;
      }
    }
    return renamed;
  });
}

// Ruins from before a ruin's stores held its rebuild cost (sim/horde.ts
// ruinStorage): raise their capacity to it.
export async function upgradeRuinStorage(db: Db, data: GameData): Promise<number> {
  return inTransaction(db, async (client) => {
    const { rows } = await client.query<{ id: number; capacity: Resources; ruin: { plots: Record<string, Plot> } }>(
      'SELECT id, capacity, ruin FROM villages WHERE ruin IS NOT NULL FOR UPDATE',
    );
    let raised = 0;
    for (const row of rows) {
      const capacity = ruinStorage(data, row.capacity, row.ruin.plots ?? {});
      if (RESOURCE_KINDS.every((kind) => capacity[kind] === row.capacity[kind])) continue;
      await client.query('UPDATE villages SET capacity = $2 WHERE id = $1', [row.id, JSON.stringify(capacity)]);
      raised++;
    }
    return raised;
  });
}

// The buildings whose 20 levels became 10 (0.23): each new level is two old ones.
export const COMPRESSED_BUILDINGS: readonly string[] = [
  'elder_hall', 'woodcutter', 'quarry', 'farm', 'iron_mine', 'storehouse', 'barracks', 'stables', 'shooting_range', 'heroes_hall',
  'scout_lodge', 'caravan_yard', 'granary_temple', 'stone_redoubt', 'longhouse_hall', 'wall', 'archer_tower', 'gate_tower', 'ballista',
  'murder_holes', 'ditch', 'watchtower', 'hospital', 'masons_guild', 'workers_huts', 'grain_silo', 'fisherman_hut', 'blacksmith', 'market',
];

// An old level of `building` on the new scale (half, rounded up).
export function compressedLevel(building: string | null, level: number): number {
  return building !== null && COMPRESSED_BUILDINGS.includes(building) ? Math.ceil(level / 2) : level;
}

function compressPlots(plots: Record<string, Plot>): Record<string, Plot> {
  return Object.fromEntries(Object.entries(plots).map(([id, p]) => [id, { ...p, level: compressedLevel(p.building, p.level) }]));
}

// The level scale a village is saved on: 1 before the 20 levels became 10
// (0.23), 2 with each level two of the old ones, 3 with the levels giving
// what the first ten did again (0.24).
export const LEVEL_SCALE = 3;

// Villages saved on an older scale. From 1: their buildings, queued builds
// (and their events) and what a ruin held, on ten levels. Then, from 1 or 2,
// their rates and stores as the levels now give them, from when each was
// last settled (what came in before then came at the old rates).
export async function upgradeLevelScale(db: Db, data: GameData): Promise<number> {
  return inTransaction(db, async (client) => {
    const { rows } = await client.query<{ id: number; world_id: number; level_scale: number }>(
      'SELECT id, world_id, level_scale FROM villages WHERE level_scale < $1 ORDER BY id FOR UPDATE',
      [LEVEL_SCALE],
    );
    for (const row of rows) {
      const village = await loadVillage(client, row.id);
      const speed = (await getWorld(client, row.world_id)).speed;
      const halve = row.level_scale === 1;
      const plots = halve ? compressPlots(village.state.plots) : village.state.plots;
      const queue = halve ? village.state.queue.map((item) => ({ ...item, targetLevel: compressedLevel(item.building, item.targetLevel) })) : village.state.queue;
      const ruinPlots = village.ruin ? (halve ? compressPlots(village.ruin.plots) : village.ruin.plots) : null;
      const state = withBonuses(data, { ...village.state, plots, levels: levelsOf(plots), queue }, village.state.bonuses, village.state.ledger.settledAt, speed);
      // A ruin's stores still hold what rebuilding it costs.
      const ledger = ruinPlots ? { ...state.ledger, capacity: ruinStorage(data, state.ledger.capacity, ruinPlots) } : state.ledger;
      await saveVillageState(client, village.id, { ...state, ledger });
      if (halve && village.ruin) await client.query('UPDATE villages SET ruin = $2 WHERE id = $1', [village.id, JSON.stringify({ ...village.ruin, plots: ruinPlots })]);
      if (halve) {
        await client.query(
          `UPDATE scheduled_events SET payload = jsonb_set(payload, '{targetLevel}', to_jsonb(ceil((payload->>'targetLevel')::numeric / 2)::int))
           WHERE status = 'pending' AND type = 'build_complete' AND (payload->>'villageId')::bigint = $1 AND payload->>'building' = ANY($2)`,
          [village.id, COMPRESSED_BUILDINGS],
        );
      }
      await client.query('UPDATE villages SET level_scale = $2 WHERE id = $1', [village.id, LEVEL_SCALE]);
    }
    return rows.length;
  });
}
