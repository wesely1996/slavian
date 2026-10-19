import { newBridge, type BridgeState } from '../sim/bridge.js';
import type { DbClient } from './pool.js';

// The world's bridge, laid down (stage 0) the first time it is asked for.
export async function loadBridge(client: DbClient, worldId: number, at: Date, sanctity: number): Promise<BridgeState> {
  await client.query('INSERT INTO bridges (world_id, state) VALUES ($1, $2) ON CONFLICT DO NOTHING', [worldId, JSON.stringify(newBridge(at, sanctity))]);
  const { rows } = await client.query<{ state: BridgeState }>('SELECT state FROM bridges WHERE world_id = $1', [worldId]);
  return rows[0]!.state;
}

// Read-only: null before anyone has touched it.
export async function findBridge(client: DbClient, worldId: number): Promise<BridgeState | null> {
  const { rows } = await client.query<{ state: BridgeState }>('SELECT state FROM bridges WHERE world_id = $1', [worldId]);
  return rows[0]?.state ?? null;
}

export async function saveBridge(client: DbClient, worldId: number, state: BridgeState): Promise<void> {
  await client.query('UPDATE bridges SET state = $2 WHERE world_id = $1', [worldId, JSON.stringify(state)]);
}
