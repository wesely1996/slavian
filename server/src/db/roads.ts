import { edgeKey } from '../sim/land.js';
import { hex, type Hex } from '../sim/hex.js';
import type { DbClient } from './pool.js';

// 'upgrading': standing at `level` while it is improved to the next;
// 'repairing': standing (damaged) while it is repaired.
export type RoadStatus = 'building' | 'standing' | 'upgrading' | 'repairing';

export interface RoadEdge {
  a: Hex;
  b: Hex;
  status: RoadStatus;
  level: number;
  // A fire reached it: half as good until repaired.
  damaged: boolean;
  builtBy: number | null;
  completesAt: Date | null;
}

interface Row {
  aq: number;
  ar: number;
  bq: number;
  br: number;
  status: RoadStatus;
  level: number;
  damaged: boolean;
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
    level: r.level,
    damaged: r.damaged,
    builtBy: r.built_by === null ? null : Number(r.built_by),
    completesAt: r.completes_at,
  }));
}

// The level of each road that stands (or is being improved), by edge key.
export async function standingRoads(client: DbClient, worldId: number): Promise<Map<string, number>> {
  return new Map((await listRoadEdges(client, worldId)).filter((e) => e.status !== 'building').map((e) => [edgeKey(e.a, e.b), e.level] as const));
}

// The roads a fire damaged that stand (or are being worked on), by edge key.
export async function damagedRoads(client: DbClient, worldId: number): Promise<Set<string>> {
  return new Set((await listRoadEdges(client, worldId)).filter((e) => e.status !== 'building' && e.damaged).map((e) => edgeKey(e.a, e.b)));
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

// A road the enemy laid in its lands: standing at once, by nobody's village.
export async function insertEnemyRoad(client: DbClient, worldId: number, a: Hex, b: Hex): Promise<void> {
  const [p, q] = ordered(a, b);
  await client.query("INSERT INTO road_edges (world_id, aq, ar, bq, br, status) VALUES ($1, $2, $3, $4, $5, 'standing') ON CONFLICT DO NOTHING", [worldId, p.q, p.r, q.q, q.r]);
}

// The work on a road is done: built, improved a level, or repaired (or a
// fire undid a repair: `damaged`).
export async function markRoadStanding(client: DbClient, worldId: number, a: Hex, b: Hex, level: number, damaged = false): Promise<void> {
  const [p, q] = ordered(a, b);
  await client.query(
    "UPDATE road_edges SET status = 'standing', level = $6, damaged = $7, completes_at = NULL WHERE world_id = $1 AND aq = $2 AND ar = $3 AND bq = $4 AND br = $5",
    [worldId, p.q, p.r, q.q, q.r, level, damaged],
  );
}

// The land under a hex sank (a lake made there): every road into it,
// standing or being worked on, is gone.
export async function deleteRoadsAt(client: DbClient, worldId: number, cell: Hex): Promise<number> {
  const { rowCount } = await client.query('DELETE FROM road_edges WHERE world_id = $1 AND ((aq = $2 AND ar = $3) OR (bq = $2 AND br = $3))', [worldId, cell.q, cell.r]);
  return rowCount ?? 0;
}

// A fire reached a road (one improved keeps on being improved).
export async function markRoadDamaged(client: DbClient, worldId: number, a: Hex, b: Hex): Promise<void> {
  const [p, q] = ordered(a, b);
  await client.query('UPDATE road_edges SET damaged = true WHERE world_id = $1 AND aq = $2 AND ar = $3 AND bq = $4 AND br = $5', [worldId, p.q, p.r, q.q, q.r]);
}

// A village starts repairing a damaged road.
export async function markRoadRepairing(client: DbClient, worldId: number, a: Hex, b: Hex, builtBy: number, completesAt: Date): Promise<void> {
  const [p, q] = ordered(a, b);
  await client.query(
    "UPDATE road_edges SET status = 'repairing', built_by = $6, completes_at = $7 WHERE world_id = $1 AND aq = $2 AND ar = $3 AND bq = $4 AND br = $5",
    [worldId, p.q, p.r, q.q, q.r, builtBy, completesAt],
  );
}

// A village starts improving a standing road to its next level.
export async function markRoadUpgrading(client: DbClient, worldId: number, a: Hex, b: Hex, builtBy: number, completesAt: Date): Promise<void> {
  const [p, q] = ordered(a, b);
  await client.query(
    "UPDATE road_edges SET status = 'upgrading', built_by = $6, completes_at = $7 WHERE world_id = $1 AND aq = $2 AND ar = $3 AND bq = $4 AND br = $5",
    [worldId, p.q, p.r, q.q, q.r, builtBy, completesAt],
  );
}
