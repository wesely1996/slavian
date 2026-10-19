// Enemy leaders (sim/leaders.ts), one alive per front.
import type { LeaderState } from '../sim/leaders.js';
import { NotFoundError } from '../errors.js';
import type { DbClient } from './pool.js';

export interface EnemyLeader extends LeaderState {
  id: number;
  worldId: number;
  front: string;
  status: 'alive' | 'dead';
  woundedUntil: Date | null;
  battles: number;
  wins: number;
  losses: number;
  razed: number;
  kills: number;
  grudgeVillageId: number | null;
  createdAt: Date;
  diedAt: Date | null;
}

interface LeaderRow {
  id: number;
  world_id: number;
  front: string;
  name: string;
  level: number;
  xp: number;
  skills: Record<string, number>;
  status: 'alive' | 'dead';
  wounded_until: Date | null;
  battles: number;
  wins: number;
  losses: number;
  razed: number;
  kills: number;
  grudge_village_id: number | null;
  created_at: Date;
  died_at: Date | null;
}

function fromRow(row: LeaderRow): EnemyLeader {
  return {
    id: row.id,
    worldId: row.world_id,
    front: row.front,
    name: row.name,
    level: row.level,
    xp: row.xp,
    skills: row.skills,
    status: row.status,
    woundedUntil: row.wounded_until,
    battles: row.battles,
    wins: row.wins,
    losses: row.losses,
    razed: row.razed,
    kills: row.kills,
    grudgeVillageId: row.grudge_village_id,
    createdAt: row.created_at,
    diedAt: row.died_at,
  };
}

// Every leader the world has seen, the living first.
export async function listLeaders(client: DbClient, worldId: number): Promise<EnemyLeader[]> {
  const { rows } = await client.query<LeaderRow>(
    "SELECT * FROM enemy_leaders WHERE world_id = $1 ORDER BY status = 'dead', front, id",
    [worldId],
  );
  return rows.map(fromRow);
}

export async function loadLeader(client: DbClient, id: number): Promise<EnemyLeader> {
  const { rows } = await client.query<LeaderRow>('SELECT * FROM enemy_leaders WHERE id = $1', [id]);
  if (!rows[0]) throw new NotFoundError('Leader not found');
  return fromRow(rows[0]);
}

export async function aliveLeader(client: DbClient, worldId: number, front: string): Promise<EnemyLeader | null> {
  const { rows } = await client.query<LeaderRow>(
    "SELECT * FROM enemy_leaders WHERE world_id = $1 AND front = $2 AND status = 'alive' FOR UPDATE",
    [worldId, front],
  );
  return rows[0] ? fromRow(rows[0]) : null;
}

export async function insertLeader(client: DbClient, worldId: number, front: string, state: LeaderState, at: Date): Promise<EnemyLeader> {
  const { rows } = await client.query<LeaderRow>(
    `INSERT INTO enemy_leaders (world_id, front, name, level, xp, skills, created_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
    [worldId, front, state.name, state.level, state.xp, JSON.stringify(state.skills), at],
  );
  return fromRow(rows[0]!);
}

export async function saveLeader(client: DbClient, leader: EnemyLeader): Promise<void> {
  await client.query(
    `UPDATE enemy_leaders SET level = $2, xp = $3, skills = $4, status = $5, wounded_until = $6, battles = $7, wins = $8,
       losses = $9, razed = $10, kills = $11, grudge_village_id = $12, died_at = $13
     WHERE id = $1`,
    [
      leader.id,
      leader.level,
      leader.xp,
      JSON.stringify(leader.skills),
      leader.status,
      leader.woundedUntil,
      leader.battles,
      leader.wins,
      leader.losses,
      leader.razed,
      leader.kills,
      leader.grudgeVillageId,
      leader.diedAt,
    ],
  );
}

// Whether the leader is at the head of a horde that is still out.
export async function leadingNow(client: DbClient, leaderId: number): Promise<boolean> {
  const { rows } = await client.query(
    "SELECT 1 FROM waves WHERE leader_id = $1 AND status NOT IN ('scheduled', 'dispersed', 'defeated', 'settled') LIMIT 1",
    [leaderId],
  );
  return rows.length > 0;
}

export async function setWaveLeader(client: DbClient, waveId: number, leaderId: number): Promise<void> {
  await client.query('UPDATE waves SET leader_id = $2 WHERE id = $1', [waveId, leaderId]);
}
