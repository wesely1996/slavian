import { NotFoundError } from '../errors.js';
import type { GeneralStatus } from '../sim/generals.js';
import type { PathStep } from '../sim/waves.js';
import type { DbClient } from './pool.js';

export interface General {
  id: number;
  worldId: number;
  accountId: number;
  name: string;
  status: GeneralStatus;
  // Where it stands (or is recruited, or heading).
  villageId: number | null;
  level: number;
  xp: number;
  // Leading this army (status 'with_army').
  armyId: number | null;
  path: PathStep[] | null;
  departsAt: Date | null;
  // Ready (recruiting) or arriving (traveling).
  until: Date | null;
}

interface GeneralRow {
  id: number;
  world_id: number;
  account_id: number;
  name: string;
  status: GeneralStatus;
  village_id: number | null;
  level: number;
  xp: number;
  army_id: number | null;
  path: PathStep[] | null;
  departs_at: Date | null;
  until: Date | null;
}

function fromRow(row: GeneralRow): General {
  return {
    id: Number(row.id),
    worldId: Number(row.world_id),
    accountId: Number(row.account_id),
    name: row.name,
    status: row.status,
    villageId: row.village_id === null ? null : Number(row.village_id),
    level: row.level,
    xp: row.xp,
    armyId: row.army_id === null ? null : Number(row.army_id),
    path: row.path,
    departsAt: row.departs_at,
    until: row.until,
  };
}

export async function insertGeneral(
  client: DbClient,
  g: Pick<General, 'worldId' | 'accountId' | 'status' | 'villageId' | 'until'> & { name: (id: number) => string },
): Promise<General> {
  const { rows } = await client.query<GeneralRow>(
    `INSERT INTO generals (world_id, account_id, name, status, village_id, until) VALUES ($1, $2, '', $3, $4, $5) RETURNING *`,
    [g.worldId, g.accountId, g.status, g.villageId, g.until],
  );
  const general = fromRow(rows[0]!);
  const named = { ...general, name: g.name(general.id) };
  await saveGeneral(client, named);
  return named;
}

export async function loadGeneral(client: DbClient, id: number): Promise<General> {
  const { rows } = await client.query<GeneralRow>('SELECT * FROM generals WHERE id = $1', [id]);
  if (!rows[0]) throw new NotFoundError(`General ${id} not found`);
  return fromRow(rows[0]);
}

export async function listGenerals(client: DbClient, worldId: number, accountId?: number): Promise<General[]> {
  const { rows } =
    accountId === undefined
      ? await client.query<GeneralRow>('SELECT * FROM generals WHERE world_id = $1 ORDER BY id', [worldId])
      : await client.query<GeneralRow>('SELECT * FROM generals WHERE world_id = $1 AND account_id = $2 ORDER BY id', [worldId, accountId]);
  return rows.map(fromRow);
}

// The general commanding a village's garrison: the best of those at home
// there (the first recruited among equals).
export async function generalAt(client: DbClient, villageId: number): Promise<General | null> {
  const { rows } = await client.query<GeneralRow>(
    `SELECT * FROM generals WHERE village_id = $1 AND status = 'home' ORDER BY level DESC, id LIMIT 1`,
    [villageId],
  );
  return rows[0] ? fromRow(rows[0]) : null;
}

export async function generalWithArmy(client: DbClient, armyId: number): Promise<General | null> {
  const { rows } = await client.query<GeneralRow>(`SELECT * FROM generals WHERE army_id = $1 AND status = 'with_army'`, [armyId]);
  return rows[0] ? fromRow(rows[0]) : null;
}

export async function saveGeneral(client: DbClient, g: General): Promise<void> {
  await client.query(
    `UPDATE generals SET name = $2, status = $3, village_id = $4, level = $5, xp = $6, army_id = $7, path = $8, departs_at = $9, until = $10
     WHERE id = $1`,
    [g.id, g.name, g.status, g.villageId, g.level, g.xp, g.armyId, g.path ? JSON.stringify(g.path) : null, g.departsAt, g.until],
  );
}

export async function deleteGeneral(client: DbClient, id: number): Promise<void> {
  await client.query('DELETE FROM generals WHERE id = $1', [id]);
}
