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
  // The enemy front that raised it in its lands (null: a player's).
  front: string | null;
  // 0: along a dry edge; 1 or 2: on the bank of `a` or `b` of a river edge.
  side: WallSide;
}

export type WallSide = 0 | 1 | 2;

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
  front: string | null;
  side: WallSide;
}

function ordered(a: Hex, b: Hex): [Hex, Hex] {
  return edgeKey(a, b).startsWith(`${a.q},${a.r}|`) ? [a, b] : [b, a];
}

export async function listEdgeWalls(client: DbClient, worldId: number): Promise<EdgeWall[]> {
  const { rows } = await client.query<Row>('SELECT * FROM edge_walls WHERE world_id = $1 ORDER BY aq, ar, bq, br, side', [worldId]);
  return rows.map((r) => ({
    a: hex(r.aq, r.ar),
    b: hex(r.bq, r.br),
    kind: r.kind,
    tier: r.tier,
    status: r.status,
    builtBy: r.built_by === null ? null : Number(r.built_by),
    ownerAccountId: r.owner_account_id === null ? null : Number(r.owner_account_id),
    completesAt: r.completes_at,
    front: r.front,
    side: r.side,
  }));
}

export async function edgeWallAt(client: DbClient, worldId: number, a: Hex, b: Hex, side: WallSide = 0): Promise<EdgeWall | null> {
  const key = edgeKey(a, b);
  return (await listEdgeWalls(client, worldId)).find((w) => edgeKey(w.a, w.b) === key && w.side === side) ?? null;
}

// Every wall along a|b (a river edge may hold one on each bank).
export async function edgeWallsAt(client: DbClient, worldId: number, a: Hex, b: Hex): Promise<EdgeWall[]> {
  const key = edgeKey(a, b);
  return (await listEdgeWalls(client, worldId)).filter((w) => edgeKey(w.a, w.b) === key);
}

export async function insertEdgeWall(client: DbClient, worldId: number, w: Omit<EdgeWall, 'tier' | 'status' | 'front'>): Promise<void> {
  const [p, q] = ordered(w.a, w.b);
  await client.query(
    "INSERT INTO edge_walls (world_id, aq, ar, bq, br, kind, tier, status, built_by, owner_account_id, completes_at, side) VALUES ($1, $2, $3, $4, $5, $6, 0, 'building', $7, $8, $9, $10)",
    [worldId, p.q, p.r, q.q, q.r, w.kind, w.builtBy, w.ownerAccountId, w.completesAt, w.side],
  );
}

export async function saveEdgeWall(client: DbClient, worldId: number, w: EdgeWall): Promise<void> {
  const [p, q] = ordered(w.a, w.b);
  await client.query(
    'UPDATE edge_walls SET kind = $6, tier = $7, status = $8, built_by = $9, completes_at = $10 WHERE world_id = $1 AND aq = $2 AND ar = $3 AND bq = $4 AND br = $5 AND side = $11',
    [worldId, p.q, p.r, q.q, q.r, w.kind, w.tier, w.status, w.builtBy, w.completesAt, w.side],
  );
}

// The side of the edge a|b whose bank is `bank`'s (stored order: a first).
export function bankSide(a: Hex, b: Hex, bank: Hex): WallSide {
  const [p] = ordered(a, b);
  return p.q === bank.q && p.r === bank.r ? 1 : 2;
}

// A wall the enemy raised in its lands (no owner), standing at once.
export async function insertEnemyWall(client: DbClient, worldId: number, a: Hex, b: Hex, front: string): Promise<void> {
  const [p, q] = ordered(a, b);
  await client.query(
    "INSERT INTO edge_walls (world_id, aq, ar, bq, br, kind, tier, status, front) VALUES ($1, $2, $3, $4, $5, 'wall', 1, 'standing', $6)",
    [worldId, p.q, p.r, q.q, q.r, front],
  );
}

export async function deleteEdgeWall(client: DbClient, worldId: number, a: Hex, b: Hex, side: WallSide = 0): Promise<void> {
  const [p, q] = ordered(a, b);
  await client.query('DELETE FROM edge_walls WHERE world_id = $1 AND aq = $2 AND ar = $3 AND bq = $4 AND br = $5 AND side = $6', [worldId, p.q, p.r, q.q, q.r, side]);
}
