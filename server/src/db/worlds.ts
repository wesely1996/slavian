import type { Difficulty, TerrainId } from '../data/index.js';
import type { QuietWindow } from '../sim/difficulty.js';
import type { Front, WorldMap } from '../sim/mapgen.js';
import { NotFoundError } from '../errors.js';
import type { DbClient } from './pool.js';

export type WorldStatus = 'lobby' | 'running' | 'won' | 'lost';

export interface World {
  id: number;
  name: string;
  seed: number;
  speed: number;
  status: WorldStatus;
  inviteCode: string | null;
  hostAccountId: number | null;
  maxPlayers: number;
  radius: number | null;
  activeFronts: Front[];
  startedAt: Date | null;
  // The Holy City's health: the run is lost at 0.
  sanctity: number;
  // The group's Svarog's Ember.
  embers: number;
  difficulty: Difficulty;
  // The group's quiet hours for horde arrivals (null: none).
  quietStart: number | null;
  quietEnd: number | null;
  quietUtcOffset: number;
}

export function quietWindow(world: World): QuietWindow | null {
  if (world.quietStart === null || world.quietEnd === null || world.quietStart === world.quietEnd) return null;
  return { start: world.quietStart, end: world.quietEnd, utcOffsetMinutes: world.quietUtcOffset };
}

export interface NewWorld {
  name: string;
  seed: number;
  speed: number;
  hostAccountId?: number;
  maxPlayers?: number;
  inviteCode?: string;
  difficulty?: Difficulty;
}

const COLUMNS = `id, name, seed, speed, status, invite_code AS "inviteCode", host_account_id AS "hostAccountId",
  max_players AS "maxPlayers", radius, active_fronts AS "activeFronts", started_at AS "startedAt", sanctity, embers,
  difficulty, quiet_start AS "quietStart", quiet_end AS "quietEnd", quiet_utc_offset AS "quietUtcOffset"`;

export async function createWorld(client: DbClient, world: NewWorld): Promise<World> {
  const { rows } = await client.query<World>(
    `INSERT INTO worlds (name, seed, speed, host_account_id, max_players, invite_code, difficulty)
     VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING ${COLUMNS}`,
    [world.name, world.seed, world.speed, world.hostAccountId ?? null, world.maxPlayers ?? 6, world.inviteCode ?? null, world.difficulty ?? 'normal'],
  );
  return rows[0]!;
}

export async function getWorld(client: DbClient, id: number): Promise<World> {
  const { rows } = await client.query<World>(`SELECT ${COLUMNS} FROM worlds WHERE id = $1`, [id]);
  if (!rows[0]) throw new NotFoundError(`World ${id} not found`);
  return rows[0];
}

export async function findWorldByInviteCode(client: DbClient, inviteCode: string): Promise<World | null> {
  const { rows } = await client.query<World>(`SELECT ${COLUMNS} FROM worlds WHERE invite_code = $1`, [inviteCode]);
  return rows[0] ?? null;
}

export async function listWorldsForAccount(client: DbClient, accountId: number): Promise<World[]> {
  const { rows } = await client.query<World>(
    `SELECT ${COLUMNS} FROM worlds
     WHERE id IN (SELECT world_id FROM world_members WHERE account_id = $1)
     ORDER BY id DESC`,
    [accountId],
  );
  return rows;
}

export interface Member {
  accountId: number;
  displayName: string;
  joinedAt: Date;
}

export async function addMember(client: DbClient, worldId: number, accountId: number): Promise<void> {
  await client.query(
    'INSERT INTO world_members (world_id, account_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
    [worldId, accountId],
  );
}

export async function listMembers(client: DbClient, worldId: number): Promise<Member[]> {
  const { rows } = await client.query<Member>(
    `SELECT m.account_id AS "accountId", a.display_name AS "displayName", m.joined_at AS "joinedAt"
     FROM world_members m JOIN accounts a ON a.id = m.account_id
     WHERE m.world_id = $1
     ORDER BY m.joined_at, m.account_id`,
    [worldId],
  );
  return rows;
}

export async function isMember(client: DbClient, worldId: number, accountId: number): Promise<boolean> {
  const { rowCount } = await client.query(
    'SELECT 1 FROM world_members WHERE world_id = $1 AND account_id = $2',
    [worldId, accountId],
  );
  return rowCount === 1;
}

export async function markStarted(client: DbClient, worldId: number, map: WorldMap, at: Date, sanctity: number): Promise<void> {
  await client.query(
    `UPDATE worlds SET status = 'running', seed = $2, radius = $3, active_fronts = $4, started_at = $5, sanctity = $6 WHERE id = $1`,
    [worldId, map.seed, map.radius, map.activeFronts, at, sanctity],
  );
}

// A horde struck the Holy City: Sanctity falls, and at 0 the run is lost.
export async function damageSanctity(client: DbClient, worldId: number, damage: number): Promise<number> {
  const { rows } = await client.query<{ sanctity: number }>(
    `UPDATE worlds SET sanctity = GREATEST(0, sanctity - $2),
       status = CASE WHEN sanctity - $2 <= 0 THEN 'lost' ELSE status END
     WHERE id = $1 RETURNING sanctity`,
    [worldId, damage],
  );
  return rows[0]!.sanctity;
}

export async function insertHexes(client: DbClient, worldId: number, map: WorldMap): Promise<void> {
  const qs: number[] = [];
  const rs: number[] = [];
  const terrain: string[] = [];
  for (const [key, type] of map.terrain) {
    const [q, r] = key.split(',').map(Number);
    qs.push(q!);
    rs.push(r!);
    terrain.push(type);
  }
  await client.query(
    `INSERT INTO hexes (world_id, q, r, terrain)
     SELECT $1, * FROM unnest($2::int[], $3::int[], $4::text[])`,
    [worldId, qs, rs, terrain],
  );
}

export async function loadHexes(client: DbClient, worldId: number): Promise<[number, number, TerrainId][]> {
  const { rows } = await client.query<{ q: number; r: number; terrain: TerrainId }>(
    'SELECT q, r, terrain FROM hexes WHERE world_id = $1 ORDER BY r, q',
    [worldId],
  );
  return rows.map((row) => [row.q, row.r, row.terrain]);
}

export async function addEmbers(client: DbClient, worldId: number, n: number): Promise<void> {
  await client.query('UPDATE worlds SET embers = embers + $2 WHERE id = $1', [worldId, n]);
}

export async function setQuietHours(client: DbClient, worldId: number, window: QuietWindow | null): Promise<void> {
  await client.query('UPDATE worlds SET quiet_start = $2, quiet_end = $3, quiet_utc_offset = $4 WHERE id = $1', [
    worldId,
    window?.start ?? null,
    window?.end ?? null,
    window?.utcOffsetMinutes ?? 0,
  ]);
}
