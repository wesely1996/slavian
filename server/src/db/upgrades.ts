// Data upgrades that need game rules, run on server start after the SQL
// migrations. Each is idempotent.
import type { GameData } from '../data/index.js';
import { HALL_PLOT, plotsFromLegacyLevels, type Plot } from '../sim/village.js';
import { ensureDigests } from '../scheduler/notices.js';
import { ensureSites } from '../scheduler/sites.js';
import { ensureHeroes } from './heroes.js';
import { getWorld } from './worlds.js';
import { inTransaction, type Db } from './pool.js';

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

// Worlds started before heroes existed: give every player theirs.
export async function upgradeHeroes(db: Db, data: GameData): Promise<number> {
  return inTransaction(db, async (client) => {
    const { rows } = await client.query<{ id: number; seed: number }>(`SELECT id, seed FROM worlds WHERE status <> 'lobby'`);
    let created = 0;
    for (const world of rows) created += await ensureHeroes(client, data, world.id, world.seed);
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
