import type { DbClient } from './pool.js';

// A horde burning an outpost down a level as it passed.
export interface Raid {
  id: number;
  worldId: number;
  waveId: number;
  villageId: number;
  q: number;
  r: number;
  levelAfter: number;
  at: Date;
}

interface RaidRow {
  id: number;
  world_id: number;
  wave_id: number;
  village_id: number;
  q: number;
  r: number;
  level_after: number;
  at: Date;
}

function fromRow(row: RaidRow): Raid {
  return {
    id: row.id,
    worldId: row.world_id,
    waveId: row.wave_id,
    villageId: row.village_id,
    q: row.q,
    r: row.r,
    levelAfter: row.level_after,
    at: row.at,
  };
}

export async function insertRaid(client: DbClient, raid: Omit<Raid, 'id'>): Promise<Raid> {
  const { rows } = await client.query<RaidRow>(
    `INSERT INTO raids (world_id, wave_id, village_id, q, r, level_after, at)
     VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
    [raid.worldId, raid.waveId, raid.villageId, raid.q, raid.r, raid.levelAfter, raid.at],
  );
  return fromRow(rows[0]!);
}

export async function listRecentRaids(client: DbClient, worldId: number, limit = 10): Promise<Raid[]> {
  const { rows } = await client.query<RaidRow>(
    'SELECT * FROM raids WHERE world_id = $1 ORDER BY at DESC, id DESC LIMIT $2',
    [worldId, limit],
  );
  return rows.map(fromRow);
}
