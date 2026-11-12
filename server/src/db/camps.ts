import type { DbClient } from './pool.js';

// What freeing a camp's captives brings (data/events.json captives).
export type CampReward = { units: Record<string, number> } | { resources: Record<'wood' | 'stone' | 'grain' | 'iron', number> };

export interface Camp {
  id: number;
  worldId: number;
  kind: 'bandit' | 'lair' | 'captives';
  front: string;
  q: number;
  r: number;
  units: Record<string, number>;
  status: 'active' | 'cleared';
  waveId: number | null;
  createdAt: Date;
  // Captives (a daily event): what freeing them brings, and when the camp
  // goes if nobody comes.
  reward?: CampReward | null;
  endsAt?: Date | null;
  // A bridge quest's lair: the quest it answers (null: none).
  quest?: string | null;
}

interface CampRow {
  id: number;
  world_id: number;
  kind: 'bandit' | 'lair' | 'captives';
  front: string;
  q: number;
  r: number;
  units: Record<string, number>;
  status: 'active' | 'cleared';
  wave_id: number | null;
  created_at: Date;
  reward: CampReward | null;
  ends_at: Date | null;
  quest: string | null;
}

function fromRow(row: CampRow): Camp {
  return {
    id: row.id,
    worldId: row.world_id,
    kind: row.kind,
    front: row.front,
    q: row.q,
    r: row.r,
    units: row.units,
    status: row.status,
    waveId: row.wave_id,
    createdAt: row.created_at,
    reward: row.reward ?? null,
    endsAt: row.ends_at ?? null,
    quest: row.quest ?? null,
  };
}

export async function insertCamp(
  client: DbClient,
  c: Pick<Camp, 'worldId' | 'kind' | 'front' | 'q' | 'r' | 'units' | 'waveId' | 'createdAt' | 'reward' | 'endsAt'> & { quest?: string | null },
): Promise<Camp> {
  const { rows } = await client.query<CampRow>(
    `INSERT INTO camps (world_id, kind, front, q, r, units, wave_id, created_at, reward, ends_at, quest) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11) RETURNING *`,
    [c.worldId, c.kind, c.front, c.q, c.r, JSON.stringify(c.units), c.waveId, c.createdAt, c.reward ? JSON.stringify(c.reward) : null, c.endsAt ?? null, c.quest ?? null],
  );
  return fromRow(rows[0]!);
}

export async function listCamps(client: DbClient, worldId: number): Promise<Camp[]> {
  const { rows } = await client.query<CampRow>(`SELECT * FROM camps WHERE world_id = $1 AND status = 'active' ORDER BY id`, [worldId]);
  return rows.map(fromRow);
}

export async function loadCamp(client: DbClient, id: number): Promise<Camp | null> {
  const { rows } = await client.query<CampRow>('SELECT * FROM camps WHERE id = $1', [id]);
  return rows[0] ? fromRow(rows[0]) : null;
}

export async function campAt(client: DbClient, worldId: number, q: number, r: number): Promise<Camp | null> {
  const { rows } = await client.query<CampRow>(`SELECT * FROM camps WHERE world_id = $1 AND q = $2 AND r = $3 AND status = 'active'`, [worldId, q, r]);
  return rows[0] ? fromRow(rows[0]) : null;
}

export async function saveCampUnits(client: DbClient, id: number, units: Record<string, number>): Promise<void> {
  await client.query('UPDATE camps SET units = $2 WHERE id = $1', [id, JSON.stringify(units)]);
}

// Gone unvisited: a daily event's time is up.
export async function deleteCamp(client: DbClient, id: number): Promise<void> {
  await client.query('DELETE FROM camps WHERE id = $1', [id]);
}

export async function markCleared(client: DbClient, id: number): Promise<void> {
  await client.query(`UPDATE camps SET status = 'cleared' WHERE id = $1`, [id]);
}
