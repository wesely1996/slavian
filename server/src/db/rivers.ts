import type { RiverEdge } from '../sim/mapgen.js';
import { listRoadEdges } from './roads.js';
import { edgeKey, landOf, type Land } from '../sim/land.js';
import { hex, type Hex } from '../sim/hex.js';
import type { DbClient } from './pool.js';
import { loadHexes } from './worlds.js';

export type Crossing = 'none' | 'building' | 'standing';

export interface StoredRiverEdge {
  a: Hex;
  b: Hex;
  crossing: Crossing;
  builtBy: number | null;
  completesAt: Date | null;
  size: number;
}

interface Row {
  aq: number;
  ar: number;
  bq: number;
  br: number;
  crossing: Crossing;
  built_by: string | null;
  completes_at: Date | null;
  size: number;
}

// Stored with a before b (edgeKey order), so each edge has one row.
function ordered(a: Hex, b: Hex): [Hex, Hex] {
  return edgeKey(a, b).startsWith(`${a.q},${a.r}|`) ? [a, b] : [b, a];
}

export async function insertRivers(client: DbClient, worldId: number, rivers: readonly RiverEdge[]): Promise<void> {
  for (const edge of rivers) {
    const [a, b] = ordered(edge.a, edge.b);
    await client.query(
      'INSERT INTO river_edges (world_id, aq, ar, bq, br, crossing, size) VALUES ($1, $2, $3, $4, $5, $6, $7) ON CONFLICT DO NOTHING',
      [worldId, a.q, a.r, b.q, b.r, edge.bridge ? 'standing' : 'none', edge.size],
    );
  }
}

export async function listRiverEdges(client: DbClient, worldId: number): Promise<StoredRiverEdge[]> {
  const { rows } = await client.query<Row>('SELECT * FROM river_edges WHERE world_id = $1 ORDER BY aq, ar, bq, br', [worldId]);
  return rows.map((r) => ({
    a: hex(r.aq, r.ar),
    b: hex(r.bq, r.br),
    crossing: r.crossing,
    builtBy: r.built_by === null ? null : Number(r.built_by),
    completesAt: r.completes_at,
    size: r.size,
  }));
}

// Every river edge (edgeKey), bridged or not.
export async function riverKeys(client: DbClient, worldId: number): Promise<Set<string>> {
  return new Set((await listRiverEdges(client, worldId)).map((e) => edgeKey(e.a, e.b)));
}

export async function riverEdge(client: DbClient, worldId: number, a: Hex, b: Hex): Promise<StoredRiverEdge | null> {
  const key = edgeKey(a, b);
  return (await listRiverEdges(client, worldId)).find((e) => edgeKey(e.a, e.b) === key) ?? null;
}

export async function setCrossing(
  client: DbClient,
  worldId: number,
  a: Hex,
  b: Hex,
  crossing: Crossing,
  builtBy: number | null = null,
  completesAt: Date | null = null,
): Promise<void> {
  const [p, q] = ordered(a, b);
  await client.query(
    'UPDATE river_edges SET crossing = $6, built_by = COALESCE($7, built_by), completes_at = $8 WHERE world_id = $1 AND aq = $2 AND ar = $3 AND bq = $4 AND br = $5',
    [worldId, p.q, p.r, q.q, q.r, crossing, builtBy, completesAt],
  );
}

// The world's terrain, its rivers without a standing bridge, and its roads.
export async function loadLand(client: DbClient, worldId: number): Promise<Land> {
  const terrain = new Map((await loadHexes(client, worldId)).map(([q, r, t]) => [`${q},${r}`, t] as const));
  const blocked = (await listRiverEdges(client, worldId)).filter((e) => e.crossing !== 'standing').map((e) => edgeKey(e.a, e.b));
  const roads = (await listRoadEdges(client, worldId)).filter((e) => e.status === 'standing').map((e) => edgeKey(e.a, e.b));
  return landOf(terrain, blocked, roads);
}
