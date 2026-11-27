// Walls along hex edges (migration 091; scheduler/edgeWalls.ts).
import { edgeKey } from '../sim/land.js';
import { hex, type Hex } from '../sim/hex.js';
import type { DbClient } from './pool.js';

// 'upgrading': standing at `tier` while it is raised to the next.
export type EdgeWallStatus = 'building' | 'standing' | 'upgrading';
// A wall, or a gatehouse (a wall with a gate for the players' own).
export type EdgeWallKind = 'wall' | 'gate';

export interface EdgeWall {
  a: Hex;
  b: Hex;
  kind: EdgeWallKind;
  // From 1 (0 while the first tier is built).
  tier: number;
  status: EdgeWallStatus;
  builtBy: number | null;
  ownerAccountId: number | null;
  completesAt: Date | null;
}

interface Row {
  aq: number;
  ar: number;
  bq: number;
  br: number;
  kind: EdgeWallKind;
  tier: number;
  status: EdgeWallStatus;
  built_by: string | number | null;
  owner_account_id: string | number | null;
  completes_at: Date | null;
}

function ordered(a: Hex, b: Hex): [Hex, Hex] {
  return edgeKey(a, b).startsWith(`${a.q},${a.r}|`) ? [a, b] : [b, a];
}

export async function listEdgeWalls(client: DbClient, worldId: number): Promise<EdgeWall[]> {
  const { rows } = await client.query<Row>('SELECT * FROM edge_walls WHERE world_id = $1 ORDER BY aq, ar, bq, br', [worldId]);
  return rows.map((r) => ({
    a: hex(r.aq, r.ar),
    b: hex(r.bq, r.br),
    kind: r.kind,
    tier: r.tier,
    status: r.status,
    builtBy: r.built_by === null ? null : Number(r.built_by),
    ownerAccountId: r.owner_account_id === null ? null : Number(r.owner_account_id),
    completesAt: r.completes_at,
  }));
}

export async function edgeWallAt(client: DbClient, worldId: number, a: Hex, b: Hex): Promise<EdgeWall | null> {
  const key = edgeKey(a, b);
  return (await listEdgeWalls(client, worldId)).find((w) => edgeKey(w.a, w.b) === key) ?? null;
}

export async function insertEdgeWall(client: DbClient, worldId: number, w: Omit<EdgeWall, 'tier' | 'status'>): Promise<void> {
  const [p, q] = ordered(w.a, w.b);
  await client.query(
    "INSERT INTO edge_walls (world_id, aq, ar, bq, br, kind, tier, status, built_by, owner_account_id, completes_at) VALUES ($1, $2, $3, $4, $5, $6, 0, 'building', $7, $8, $9)",
    [worldId, p.q, p.r, q.q, q.r, w.kind, w.builtBy, w.ownerAccountId, w.completesAt],
  );
}

export async function saveEdgeWall(client: DbClient, worldId: number, w: EdgeWall): Promise<void> {
  const [p, q] = ordered(w.a, w.b);
  await client.query(
    'UPDATE edge_walls SET kind = $6, tier = $7, status = $8, built_by = $9, completes_at = $10 WHERE world_id = $1 AND aq = $2 AND ar = $3 AND bq = $4 AND br = $5',
    [worldId, p.q, p.r, q.q, q.r, w.kind, w.tier, w.status, w.builtBy, w.completesAt],
  );
}

export async function deleteEdgeWall(client: DbClient, worldId: number, a: Hex, b: Hex): Promise<void> {
  const [p, q] = ordered(a, b);
  await client.query('DELETE FROM edge_walls WHERE world_id = $1 AND aq = $2 AND ar = $3 AND bq = $4 AND br = $5', [worldId, p.q, p.r, q.q, q.r]);
}
