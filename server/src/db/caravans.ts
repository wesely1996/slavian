import { NotFoundError } from '../errors.js';
import type { Resources } from '../sim/resources.js';
import type { PathStep } from '../sim/waves.js';
import type { DbClient } from './pool.js';

export type CaravanKind = 'deliver' | 'fetch';
export type CaravanStatus = 'outbound' | 'returning' | 'done';

export interface Caravan {
  id: number;
  worldId: number;
  villageId: number;
  // null: the Holy City vault.
  destinationVillageId: number | null;
  kind: CaravanKind;
  caravans: number;
  cargo: Resources;
  carriedBack: Resources | null;
  status: CaravanStatus;
  path: PathStep[];
  departsAt: Date;
  arrivesAt: Date;
  returnsAt: Date;
}

interface CaravanRow {
  id: number;
  world_id: number;
  village_id: number;
  destination_village_id: number | null;
  kind: CaravanKind;
  caravans: number;
  cargo: Resources;
  carried_back: Resources | null;
  status: CaravanStatus;
  path: PathStep[];
  departs_at: Date;
  arrives_at: Date;
  returns_at: Date;
}

function fromRow(row: CaravanRow): Caravan {
  return {
    id: row.id,
    worldId: row.world_id,
    villageId: row.village_id,
    destinationVillageId: row.destination_village_id,
    kind: row.kind,
    caravans: row.caravans,
    cargo: row.cargo,
    carriedBack: row.carried_back,
    status: row.status,
    path: row.path,
    departsAt: row.departs_at,
    arrivesAt: row.arrives_at,
    returnsAt: row.returns_at,
  };
}

export async function insertCaravan(
  client: DbClient,
  caravan: Omit<Caravan, 'id' | 'carriedBack' | 'status'>,
): Promise<Caravan> {
  const { rows } = await client.query<CaravanRow>(
    `INSERT INTO caravans
       (world_id, village_id, destination_village_id, kind, caravans, cargo, path, departs_at, arrives_at, returns_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) RETURNING *`,
    [
      caravan.worldId,
      caravan.villageId,
      caravan.destinationVillageId,
      caravan.kind,
      caravan.caravans,
      JSON.stringify(caravan.cargo),
      JSON.stringify(caravan.path),
      caravan.departsAt,
      caravan.arrivesAt,
      caravan.returnsAt,
    ],
  );
  return fromRow(rows[0]!);
}

export async function loadCaravan(client: DbClient, id: number): Promise<Caravan> {
  const { rows } = await client.query<CaravanRow>('SELECT * FROM caravans WHERE id = $1', [id]);
  if (!rows[0]) throw new NotFoundError(`Caravan ${id} not found`);
  return fromRow(rows[0]);
}

export async function markReturning(client: DbClient, id: number, carriedBack: Resources): Promise<void> {
  await client.query(`UPDATE caravans SET status = 'returning', carried_back = $2 WHERE id = $1`, [
    id,
    JSON.stringify(carriedBack),
  ]);
}

export async function markCaravanDone(client: DbClient, id: number): Promise<void> {
  await client.query(`UPDATE caravans SET status = 'done' WHERE id = $1`, [id]);
}

// Caravans of a village still on the road.
export async function caravansOut(client: DbClient, villageId: number): Promise<number> {
  const { rows } = await client.query<{ n: string | null }>(
    `SELECT sum(caravans) AS n FROM caravans WHERE village_id = $1 AND status <> 'done'`,
    [villageId],
  );
  return Number(rows[0]?.n ?? 0);
}

// Trips on the road, plus the most recent finished ones.
export async function listCaravans(client: DbClient, worldId: number, recentDone = 5): Promise<Caravan[]> {
  const { rows } = await client.query<CaravanRow>(
    `(SELECT * FROM caravans WHERE world_id = $1 AND status <> 'done')
     UNION ALL
     (SELECT * FROM caravans WHERE world_id = $1 AND status = 'done' ORDER BY returns_at DESC LIMIT $2)
     ORDER BY departs_at DESC, id DESC`,
    [worldId, recentDone],
  );
  return rows.map(fromRow);
}
