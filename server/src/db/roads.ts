import { edgeKey } from '../sim/land.js';
import { hex, type Hex } from '../sim/hex.js';
import type { DbClient } from './pool.js';

export type RoadStatus = 'building' | 'standing';

export interface RoadEdge {
  a: Hex;
  b: Hex;
  status: RoadStatus;
  builtBy: number | null;
  completesAt: Date | null;
}

interface Row {
  aq: number;
  ar: number;
  bq: number;
  br: number;
  status: RoadStatus;
  built_by: string | null;
  completes_at: Date | null;
}

// Stored with a before b (edgeKey order), so each edge has one row.
function ordered(a: Hex, b: Hex): [Hex, Hex] {
  return edgeKey(a, b).startsWith(`${a.q},${a.r}|`) ? [a, b] : [b, a];
}

export async function listRoadEdges(client: DbClient, worldId: number): Promise<RoadEdge[]> {
  const { rows } = await client.query<Row>('SELECT * FROM road_edges WHERE world_id = $1 ORDER BY aq, ar, bq, br', [worldId]);
  return rows.map((r) => ({
    a: hex(r.aq, r.ar),
    b: hex(r.bq, r.br),
    status: r.status,
    builtBy: r.built_by === null ? null : Number(r.built_by),
    completesAt: r.completes_at,
  }));
}

export async function roadEdge(client: DbClient, worldId: number, a: Hex, b: Hex): Promise<RoadEdge | null> {
  const key = edgeKey(a, b);
  return (await listRoadEdges(client, worldId)).find((e) => edgeKey(e.a, e.b) === key) ?? null;
}

export async function insertRoad(client: DbClient, worldId: number, a: Hex, b: Hex, builtBy: number, completesAt: Date): Promise<void> {
  const [p, q] = ordered(a, b);
  await client.query(
    "INSERT INTO road_edges (world_id, aq, ar, bq, br, status, built_by, completes_at) VALUES ($1, $2, $3, $4, $5, 'building', $6, $7)",
    [worldId, p.q, p.r, q.q, q.r, builtBy, completesAt],
  );
}

export async function markRoadStanding(client: DbClient, worldId: number, a: Hex, b: Hex): Promise<void> {
  const [p, q] = ordered(a, b);
  await client.query(
    "UPDATE road_edges SET status = 'standing', completes_at = NULL WHERE world_id = $1 AND aq = $2 AND ar = $3 AND bq = $4 AND br = $5",
    [worldId, p.q, p.r, q.q, q.r],
  );
}
