import { NotFoundError } from '../errors.js';
import type { PathStep } from '../sim/waves.js';
import type { DbClient } from './pool.js';

export type ExpeditionStatus = 'outbound' | 'returning' | 'founded' | 'done';

export interface Expedition {
  id: number;
  worldId: number;
  villageId: number;
  q: number;
  r: number;
  name: string;
  settlers: number;
  status: ExpeditionStatus;
  failure: string | null;
  foundedVillageId: number | null;
  path: PathStep[];
  departsAt: Date;
  arrivesAt: Date;
  returnsAt: Date;
}

interface ExpeditionRow {
  id: number;
  world_id: number;
  village_id: number;
  q: number;
  r: number;
  name: string;
  settlers: number;
  status: ExpeditionStatus;
  failure: string | null;
  founded_village_id: number | null;
  path: PathStep[];
  departs_at: Date;
  arrives_at: Date;
  returns_at: Date;
}

function fromRow(row: ExpeditionRow): Expedition {
  return {
    id: row.id,
    worldId: row.world_id,
    villageId: row.village_id,
    q: row.q,
    r: row.r,
    name: row.name,
    settlers: row.settlers,
    status: row.status,
    failure: row.failure,
    foundedVillageId: row.founded_village_id,
    path: row.path,
    departsAt: row.departs_at,
    arrivesAt: row.arrives_at,
    returnsAt: row.returns_at,
  };
}

export async function insertExpedition(
  client: DbClient,
  e: Omit<Expedition, 'id' | 'status' | 'failure' | 'foundedVillageId'>,
): Promise<Expedition> {
  const { rows } = await client.query<ExpeditionRow>(
    `INSERT INTO expeditions (world_id, village_id, q, r, name, settlers, path, departs_at, arrives_at, returns_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) RETURNING *`,
    [e.worldId, e.villageId, e.q, e.r, e.name, e.settlers, JSON.stringify(e.path), e.departsAt, e.arrivesAt, e.returnsAt],
  );
  return fromRow(rows[0]!);
}

export async function loadExpedition(client: DbClient, id: number): Promise<Expedition> {
  const { rows } = await client.query<ExpeditionRow>('SELECT * FROM expeditions WHERE id = $1', [id]);
  if (!rows[0]) throw new NotFoundError(`Expedition ${id} not found`);
  return fromRow(rows[0]);
}

export async function markFounded(client: DbClient, id: number, villageId: number): Promise<void> {
  await client.query(`UPDATE expeditions SET status = 'founded', founded_village_id = $2 WHERE id = $1`, [id, villageId]);
}

export async function markTurnedBack(client: DbClient, id: number, failure: string): Promise<void> {
  await client.query(`UPDATE expeditions SET status = 'returning', failure = $2 WHERE id = $1`, [id, failure]);
}

export async function markExpeditionDone(client: DbClient, id: number): Promise<void> {
  await client.query(`UPDATE expeditions SET status = 'done' WHERE id = $1`, [id]);
}

// Expeditions on their way to a hex (anyone's).
export async function outboundTo(client: DbClient, worldId: number, q: number, r: number): Promise<boolean> {
  const { rows } = await client.query(
    `SELECT 1 FROM expeditions WHERE world_id = $1 AND q = $2 AND r = $3 AND status = 'outbound'`,
    [worldId, q, r],
  );
  return rows.length > 0;
}

// On the road, plus the latest few that ended.
export async function listExpeditions(client: DbClient, worldId: number, recent = 5): Promise<Expedition[]> {
  const { rows } = await client.query<ExpeditionRow>(
    `(SELECT * FROM expeditions WHERE world_id = $1 AND status IN ('outbound', 'returning'))
     UNION ALL
     (SELECT * FROM expeditions WHERE world_id = $1 AND status IN ('founded', 'done') ORDER BY arrives_at DESC LIMIT $2)
     ORDER BY departs_at DESC, id DESC`,
    [worldId, recent],
  );
  return rows.map(fromRow);
}

export async function countVillagesOwned(client: DbClient, worldId: number, accountId: number): Promise<number> {
  const { rows } = await client.query<{ n: string }>(
    'SELECT count(*) AS n FROM villages WHERE world_id = $1 AND owner_account_id = $2',
    [worldId, accountId],
  );
  return Number(rows[0]!.n);
}
