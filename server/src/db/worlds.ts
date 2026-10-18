import type { DbClient } from './pool.js';

export interface World {
  id: number;
  name: string;
  seed: number;
  speed: number;
}

export async function createWorld(client: DbClient, world: Omit<World, 'id'>): Promise<World> {
  const { rows } = await client.query<World>(
    'INSERT INTO worlds (name, seed, speed) VALUES ($1, $2, $3) RETURNING id, name, seed, speed',
    [world.name, world.seed, world.speed],
  );
  return rows[0]!;
}

export async function getWorld(client: DbClient, id: number): Promise<World> {
  const { rows } = await client.query<World>('SELECT id, name, seed, speed FROM worlds WHERE id = $1', [id]);
  if (!rows[0]) throw new Error(`World ${id} not found`);
  return rows[0];
}
