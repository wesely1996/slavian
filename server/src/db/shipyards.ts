// Shipyards: the group's river-boat projects (data/events.json `shipyard`).
import { hex, type Hex } from '../sim/hex.js';
import type { Resources } from '../sim/resources.js';
import type { DbClient } from './pool.js';

export type ShipyardStatus = 'open' | 'building' | 'done';

export interface Shipyard {
  id: number;
  worldId: number;
  q: number;
  r: number;
  // The river edge it is built on.
  edge: { a: Hex; b: Hex };
  status: ShipyardStatus;
  cost: Resources;
  paid: Resources;
  front: string;
  raiders: Record<string, number>;
  raids: number;
  // Times raiders burned its work (shipyard.maxBurns: it is lost).
  burns: number;
  endsAt: Date | null;
  completesAt: Date | null;
  nextRaidAt: Date | null;
}

interface Row {
  id: string;
  world_id: string;
  q: number;
  r: number;
  aq: number;
  ar: number;
  bq: number;
  br: number;
  status: ShipyardStatus;
  cost: Resources;
  paid: Resources;
  front: string;
  raiders: Record<string, number>;
  raids: number;
  burns: number | null;
  ends_at: Date | null;
  completes_at: Date | null;
  next_raid_at: Date | null;
}

function fromRow(r: Row): Shipyard {
  return {
    id: Number(r.id),
    worldId: Number(r.world_id),
    q: r.q,
    r: r.r,
    edge: { a: hex(r.aq, r.ar), b: hex(r.bq, r.br) },
    status: r.status,
    cost: r.cost,
    paid: r.paid,
    front: r.front,
    raiders: r.raiders,
    raids: r.raids,
    burns: r.burns ?? 0,
    endsAt: r.ends_at,
    completesAt: r.completes_at,
    nextRaidAt: r.next_raid_at,
  };
}

export async function insertShipyard(
  client: DbClient,
  worldId: number,
  input: { cell: Hex; edge: { a: Hex; b: Hex }; cost: Resources; front: string; raiders: Record<string, number>; endsAt: Date },
): Promise<number> {
  const none: Resources = { wood: 0, stone: 0, grain: 0, iron: 0 };
  const { rows } = await client.query<{ id: string }>(
    `INSERT INTO shipyards (world_id, q, r, aq, ar, bq, br, status, cost, paid, front, raiders, ends_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, 'open', $8, $9, $10, $11, $12) RETURNING id`,
    [worldId, input.cell.q, input.cell.r, input.edge.a.q, input.edge.a.r, input.edge.b.q, input.edge.b.r,
      JSON.stringify(input.cost), JSON.stringify(none), input.front, JSON.stringify(input.raiders), input.endsAt],
  );
  return Number(rows[0]!.id);
}

export async function listShipyards(client: DbClient, worldId: number): Promise<Shipyard[]> {
  const { rows } = await client.query<Row>('SELECT * FROM shipyards WHERE world_id = $1 ORDER BY id', [worldId]);
  return rows.map(fromRow);
}

export async function loadShipyard(client: DbClient, id: number): Promise<Shipyard | null> {
  const { rows } = await client.query<Row>('SELECT * FROM shipyards WHERE id = $1', [id]);
  return rows[0] ? fromRow(rows[0]) : null;
}

export async function saveShipyard(client: DbClient, s: Shipyard): Promise<void> {
  await client.query(
    `UPDATE shipyards SET status = $2, paid = $3, raids = $4, completes_at = $5, next_raid_at = $6, burns = $7 WHERE id = $1`,
    [s.id, s.status, JSON.stringify(s.paid), s.raids, s.completesAt, s.nextRaidAt, s.burns],
  );
}

export async function deleteShipyard(client: DbClient, id: number): Promise<void> {
  await client.query('DELETE FROM shipyards WHERE id = $1', [id]);
}
