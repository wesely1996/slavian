import type { FortPlots, FortWork } from '../sim/forts.js';
import type { DbClient } from './pool.js';

// A fort, or a supply point (a grain store with no walls).
export type FortKind = 'fort' | 'supply';

export interface Fort {
  id: number;
  kind: FortKind;
  worldId: number;
  ownerAccountId: number | null;
  villageId: number | null;
  q: number;
  r: number;
  status: 'building' | 'standing';
  completesAt: Date;
  // The last time an army held it.
  mannedAt: Date | null;
  // Grain kept there for armies standing on it.
  grain: number;
  // How low that grain may fall for armies (null: to the last).
  armyFloor: number | null;
  // Nobody's (a mountain city's supply point): any army draws on it, any
  // caravan fills it; no horde burns it, no bandit takes it.
  neutral: boolean;
  // A fort's buildings (forts.json; none for a supply point) and the one rising.
  plots: FortPlots;
  work: FortWork | null;
  // The Fort Garrison's defenders (unit -> count), who never leave it.
  defenders: Record<string, number>;
}

interface FortRow {
  id: number;
  kind: FortKind;
  world_id: number;
  owner_account_id: number | null;
  village_id: number | null;
  q: number;
  r: number;
  status: 'building' | 'standing';
  completes_at: Date;
  manned_at: Date | null;
  grain: number;
  army_floor: number | null;
  neutral: boolean | null;
  plots: FortPlots | null;
  work: FortWork | null;
  defenders: Record<string, number> | null;
}

function fromRow(row: FortRow): Fort {
  return {
    id: row.id,
    kind: row.kind,
    worldId: row.world_id,
    ownerAccountId: row.owner_account_id,
    villageId: row.village_id,
    q: row.q,
    r: row.r,
    status: row.status,
    completesAt: row.completes_at,
    mannedAt: row.manned_at,
    grain: row.grain,
    armyFloor: row.army_floor === null || row.army_floor === undefined ? null : Number(row.army_floor),
    neutral: row.neutral ?? false,
    plots: row.plots ?? {},
    work: row.work ?? null,
    defenders: row.defenders ?? {},
  };
}

export async function insertFort(client: DbClient, f: Pick<Fort, 'kind' | 'worldId' | 'ownerAccountId' | 'villageId' | 'q' | 'r' | 'completesAt' | 'plots'>): Promise<Fort> {
  const { rows } = await client.query<FortRow>(
    `INSERT INTO forts (kind, world_id, owner_account_id, village_id, q, r, completes_at, manned_at, plots) VALUES ($1, $2, $3, $4, $5, $6, $7, $7, $8) RETURNING *`,
    [f.kind, f.worldId, f.ownerAccountId, f.villageId, f.q, f.r, f.completesAt, JSON.stringify(f.plots)],
  );
  return fromRow(rows[0]!);
}

// A neutral supply point, standing at once (a built mountain city's).
export async function insertNeutralSupply(client: DbClient, worldId: number, q: number, r: number, at: Date): Promise<Fort> {
  const { rows } = await client.query<FortRow>(
    `INSERT INTO forts (kind, world_id, owner_account_id, village_id, q, r, completes_at, manned_at, status, neutral)
     VALUES ('supply', $1, NULL, NULL, $2, $3, $4, $4, 'standing', true) RETURNING *`,
    [worldId, q, r, at],
  );
  return fromRow(rows[0]!);
}

// The fort on a hex, or (with no `kind`, and no fort there) its supply point.
export async function fortAt(client: DbClient, worldId: number, q: number, r: number, kind?: FortKind): Promise<Fort | null> {
  const { rows } = kind
    ? await client.query<FortRow>('SELECT * FROM forts WHERE world_id = $1 AND q = $2 AND r = $3 AND kind = $4', [worldId, q, r, kind])
    : await client.query<FortRow>(`SELECT * FROM forts WHERE world_id = $1 AND q = $2 AND r = $3 ORDER BY (kind <> 'fort'), id LIMIT 1`, [worldId, q, r]);
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

export async function setFortGrain(client: DbClient, id: number, grain: number): Promise<void> {
  await client.query('UPDATE forts SET grain = $2 WHERE id = $1', [id, grain]);
}

export async function setFortFloor(client: DbClient, id: number, floor: number | null): Promise<void> {
  await client.query('UPDATE forts SET army_floor = $2 WHERE id = $1', [id, floor]);
}

export async function saveFortBuildings(client: DbClient, id: number, plots: FortPlots, work: FortWork | null): Promise<void> {
  await client.query('UPDATE forts SET plots = $2, work = $3 WHERE id = $1', [id, JSON.stringify(plots), work === null ? null : JSON.stringify(work)]);
}

export async function setFortDefenders(client: DbClient, id: number, defenders: Record<string, number>): Promise<void> {
  await client.query('UPDATE forts SET defenders = $2 WHERE id = $1', [id, JSON.stringify(defenders)]);
}

// Whether the fort has defenders of its own.
export function manned(fort: Pick<Fort, 'defenders'>): boolean {
  return Object.values(fort.defenders).some((n) => n > 0);
}
