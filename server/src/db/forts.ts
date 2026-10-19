import type { DbClient } from './pool.js';

export interface Fort {
  id: number;
  worldId: number;
  ownerAccountId: number | null;
  villageId: number | null;
  q: number;
  r: number;
  status: 'building' | 'standing';
  completesAt: Date;
  // The last time an army held it.
  mannedAt: Date | null;
}

interface FortRow {
  id: number;
  world_id: number;
  owner_account_id: number | null;
  village_id: number | null;
  q: number;
  r: number;
  status: 'building' | 'standing';
  completes_at: Date;
  manned_at: Date | null;
}

function fromRow(row: FortRow): Fort {
  return {
    id: row.id,
    worldId: row.world_id,
    ownerAccountId: row.owner_account_id,
    villageId: row.village_id,
    q: row.q,
    r: row.r,
    status: row.status,
    completesAt: row.completes_at,
    mannedAt: row.manned_at,
  };
}

export async function insertFort(client: DbClient, f: Pick<Fort, 'worldId' | 'ownerAccountId' | 'villageId' | 'q' | 'r' | 'completesAt'>): Promise<Fort> {
  const { rows } = await client.query<FortRow>(
    `INSERT INTO forts (world_id, owner_account_id, village_id, q, r, completes_at, manned_at) VALUES ($1, $2, $3, $4, $5, $6, $6) RETURNING *`,
    [f.worldId, f.ownerAccountId, f.villageId, f.q, f.r, f.completesAt],
  );
  return fromRow(rows[0]!);
}

export async function fortAt(client: DbClient, worldId: number, q: number, r: number): Promise<Fort | null> {
  const { rows } = await client.query<FortRow>('SELECT * FROM forts WHERE world_id = $1 AND q = $2 AND r = $3', [worldId, q, r]);
  return rows[0] ? fromRow(rows[0]) : null;
}

export async function loadFort(client: DbClient, id: number): Promise<Fort | null> {
  const { rows } = await client.query<FortRow>('SELECT * FROM forts WHERE id = $1', [id]);
  return rows[0] ? fromRow(rows[0]) : null;
}

export async function listForts(client: DbClient, worldId: number): Promise<Fort[]> {
  const { rows } = await client.query<FortRow>('SELECT * FROM forts WHERE world_id = $1 ORDER BY id', [worldId]);
  return rows.map(fromRow);
}

export async function markFortStanding(client: DbClient, id: number): Promise<void> {
  await client.query(`UPDATE forts SET status = 'standing' WHERE id = $1`, [id]);
}

export async function markFortManned(client: DbClient, id: number, at: Date): Promise<void> {
  await client.query('UPDATE forts SET manned_at = $2 WHERE id = $1', [id, at]);
}

export async function deleteFort(client: DbClient, id: number): Promise<void> {
  await client.query('DELETE FROM forts WHERE id = $1', [id]);
}
