import type { DbClient } from './pool.js';

export async function addFear(client: DbClient, worldId: number, q: number, r: number, amount: number): Promise<void> {
  if (amount <= 0) return;
  await client.query(
    `INSERT INTO fear (world_id, q, r, value) VALUES ($1, $2, $3, $4)
     ON CONFLICT (world_id, q, r) DO UPDATE SET value = fear.value + EXCLUDED.value`,
    [worldId, q, r, amount],
  );
}

// A new wave sets out: older memories fade.
export async function decayFear(client: DbClient, worldId: number, factor: number, minimum: number): Promise<void> {
  await client.query('UPDATE fear SET value = value * $2 WHERE world_id = $1', [worldId, factor]);
  await client.query('DELETE FROM fear WHERE world_id = $1 AND value < $2', [worldId, minimum]);
}

export async function loadFear(client: DbClient, worldId: number): Promise<Map<string, number>> {
  const { rows } = await client.query<{ q: number; r: number; value: number }>('SELECT q, r, value FROM fear WHERE world_id = $1', [worldId]);
  return new Map(rows.map((row) => [`${row.q},${row.r}`, row.value]));
}
