// The ground of a battle's hex (sim/ground.ts), from the world's terrain
// and its rivers.
import type { GameData } from '../data/index.js';
import type { DbClient } from '../db/pool.js';
import { listRiverEdges } from '../db/rivers.js';
import { loadHexes } from '../db/worlds.js';
import { groundAt, type Ground } from '../sim/ground.js';
import type { Hex } from '../sim/hex.js';
import { edgeKey } from '../sim/land.js';

export async function groundOf(client: DbClient, data: GameData, worldId: number, cell: Hex): Promise<Ground> {
  const terrain = new Map((await loadHexes(client, worldId)).map(([q, r, t]) => [`${q},${r}`, t] as const));
  const rivers = new Set((await listRiverEdges(client, worldId)).map((e) => edgeKey(e.a, e.b)));
  return groundAt(data, terrain, rivers, cell);
}
