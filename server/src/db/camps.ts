import type { DbClient } from './pool.js';

export interface Camp {
  id: number;
  worldId: number;
  kind: 'bandit' | 'lair';
  front: string;
  q: number;
  r: number;
  units: Record<string, number>;
  status: 'active' | 'cleared';
  waveId: number | null;
  createdAt: Date;
}

interface CampRow {
  id: number;
  world_id: number;
  kind: 'bandit' | 'lair';
  front: string;
  q: number;
  r: number;
  units: Record<string, number>;
  status: 'active' | 'cleared';
  wave_id: number | null;
  created_at: Date;
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
  };
}

export async function insertCamp(client: DbClient, c: Pick<Camp, 'worldId' | 'kind' | 'front' | 'q' | 'r' | 'units' | 'waveId' | 'createdAt'>): Promise<Camp> {
  const { rows } = await client.query<CampRow>(
    `INSERT INTO camps (world_id, kind, front, q, r, units, wave_id, created_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *`,
    [c.worldId, c.kind, c.front, c.q, c.r, JSON.stringify(c.units), c.waveId, c.createdAt],
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

export async function markCleared(client: DbClient, id: number): Promise<void> {
  await client.query(`UPDATE camps SET status = 'cleared' WHERE id = $1`, [id]);
}
