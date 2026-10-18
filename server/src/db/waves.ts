import { NotFoundError } from '../errors.js';
import type { Stance } from '../data/index.js';
import type { Front } from '../sim/mapgen.js';
import type { Composition, March, PathStep, PlannedWave } from '../sim/waves.js';
import type { DbClient } from './pool.js';

export type WaveStatus = 'scheduled' | 'marching' | 'arrived' | 'battling' | 'defeated' | 'dispersed';

export interface Wave {
  id: number;
  worldId: number;
  index: number;
  front: Front;
  status: WaveStatus;
  threat: string;
  stance: Stance;
  // Current strength: shrinks as the horde takes losses in battle.
  composition: Composition;
  spawnAt: Date;
  spawn: { q: number; r: number } | null;
  targetVillageId: number | null;
  path: PathStep[] | null;
  arrivesAt: Date | null;
  endsAt: Date | null;
}

interface WaveRow {
  id: number;
  world_id: number;
  index: number;
  front: Front;
  status: WaveStatus;
  threat: string;
  stance: Stance;
  composition: Composition;
  spawn_at: Date;
  spawn_q: number | null;
  spawn_r: number | null;
  target_village_id: number | null;
  path: PathStep[] | null;
  arrives_at: Date | null;
  ends_at: Date | null;
}

function fromRow(row: WaveRow): Wave {
  return {
    id: row.id,
    worldId: row.world_id,
    index: row.index,
    front: row.front,
    status: row.status,
    threat: row.threat,
    stance: row.stance,
    composition: row.composition,
    spawnAt: row.spawn_at,
    spawn: row.spawn_q === null || row.spawn_r === null ? null : { q: row.spawn_q, r: row.spawn_r },
    targetVillageId: row.target_village_id,
    path: row.path,
    arrivesAt: row.arrives_at,
    endsAt: row.ends_at,
  };
}

export async function insertWave(client: DbClient, worldId: number, wave: PlannedWave): Promise<Wave> {
  const { rows } = await client.query<WaveRow>(
    `INSERT INTO waves (world_id, index, front, threat, stance, composition, spawn_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
    [worldId, wave.index, wave.front, wave.threat, wave.stance, JSON.stringify(wave.composition), wave.spawnAt],
  );
  return fromRow(rows[0]!);
}

export async function loadWave(client: DbClient, id: number): Promise<Wave> {
  const { rows } = await client.query<WaveRow>('SELECT * FROM waves WHERE id = $1', [id]);
  if (!rows[0]) throw new NotFoundError(`Wave ${id} not found`);
  return fromRow(rows[0]);
}

export async function lastWave(client: DbClient, worldId: number): Promise<Wave | null> {
  const { rows } = await client.query<WaveRow>(
    'SELECT * FROM waves WHERE world_id = $1 ORDER BY index DESC LIMIT 1',
    [worldId],
  );
  return rows[0] ? fromRow(rows[0]) : null;
}

// Waves players should know about: everything still on the board.
export async function listActiveWaves(client: DbClient, worldId: number): Promise<Wave[]> {
  const { rows } = await client.query<WaveRow>(
    "SELECT * FROM waves WHERE world_id = $1 AND status NOT IN ('dispersed', 'defeated') ORDER BY index",
    [worldId],
  );
  return rows.map(fromRow);
}

export async function markMarching(client: DbClient, id: number, march: March): Promise<void> {
  await client.query(
    `UPDATE waves SET status = 'marching', spawn_q = $2, spawn_r = $3, target_village_id = $4, path = $5, arrives_at = $6
     WHERE id = $1`,
    [id, march.spawn.q, march.spawn.r, march.targetVillageId, JSON.stringify(march.path), march.arrivesAt],
  );
}

export async function markArrived(client: DbClient, id: number, endsAt: Date): Promise<void> {
  await client.query("UPDATE waves SET status = 'arrived', ends_at = $2 WHERE id = $1", [id, endsAt]);
}

export async function markDispersed(client: DbClient, id: number): Promise<void> {
  await client.query("UPDATE waves SET status = 'dispersed' WHERE id = $1", [id]);
}

export async function markBattling(client: DbClient, id: number): Promise<void> {
  await client.query("UPDATE waves SET status = 'battling' WHERE id = $1", [id]);
}

export async function setWaveStrength(client: DbClient, id: number, composition: Composition): Promise<void> {
  await client.query('UPDATE waves SET composition = $2 WHERE id = $1', [id, JSON.stringify(composition)]);
}

// Battle over: beaten ('defeated') or done raiding ('dispersed').
export async function endWave(client: DbClient, id: number, status: 'defeated' | 'dispersed', at: Date): Promise<void> {
  await client.query('UPDATE waves SET status = $2, ends_at = $3 WHERE id = $1', [id, status, at]);
}

// After a field battle the horde won: back on the road, later than planned.
export async function resumeMarch(client: DbClient, id: number, path: PathStep[], arrivesAt: Date): Promise<void> {
  await client.query(`UPDATE waves SET status = 'marching', path = $2, arrives_at = $3 WHERE id = $1`, [
    id,
    JSON.stringify(path),
    arrivesAt,
  ]);
}
