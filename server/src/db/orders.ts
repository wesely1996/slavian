import type { StandingOrder } from '../sim/orders.js';
import type { DbClient } from './pool.js';

export interface StoredOrder {
  id: number;
  worldId: number;
  villageId: number;
  spec: StandingOrder;
  lastResult: string | null;
  lastRunAt: Date | null;
  createdAt: Date;
}

interface OrderRow {
  id: number;
  world_id: number;
  village_id: number;
  spec: StandingOrder;
  last_result: string | null;
  last_run_at: Date | null;
  created_at: Date;
}

function fromRow(row: OrderRow): StoredOrder {
  return {
    id: row.id,
    worldId: row.world_id,
    villageId: row.village_id,
    spec: row.spec,
    lastResult: row.last_result,
    lastRunAt: row.last_run_at,
    createdAt: row.created_at,
  };
}

export async function insertOrder(
  client: DbClient,
  order: { worldId: number; villageId: number; spec: StandingOrder; createdAt: Date },
): Promise<StoredOrder> {
  const { rows } = await client.query<OrderRow>(
    'INSERT INTO standing_orders (world_id, village_id, spec, created_at) VALUES ($1, $2, $3, $4) RETURNING *',
    [order.worldId, order.villageId, JSON.stringify(order.spec), order.createdAt],
  );
  return fromRow(rows[0]!);
}

export async function listOrders(client: DbClient, filter: { worldId?: number; villageId?: number }): Promise<StoredOrder[]> {
  const { rows } = await client.query<OrderRow>(
    `SELECT * FROM standing_orders WHERE ($1::bigint IS NULL OR world_id = $1) AND ($2::bigint IS NULL OR village_id = $2)
     ORDER BY id`,
    [filter.worldId ?? null, filter.villageId ?? null],
  );
  return rows.map(fromRow);
}

export async function deleteOrder(client: DbClient, villageId: number, id: number): Promise<boolean> {
  const { rowCount } = await client.query('DELETE FROM standing_orders WHERE id = $1 AND village_id = $2', [id, villageId]);
  return (rowCount ?? 0) > 0;
}

export async function recordOrderRun(client: DbClient, id: number, result: string, at: Date): Promise<void> {
  await client.query('UPDATE standing_orders SET last_result = $2, last_run_at = $3 WHERE id = $1', [id, result, at]);
}
