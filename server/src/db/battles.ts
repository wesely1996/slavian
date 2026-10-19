import type { Stance } from '../data/index.js';
import { NotFoundError } from '../errors.js';
import type { Resources } from '../sim/resources.js';
import type { Units } from '../sim/training.js';
import type { DbClient } from './pool.js';

export type BattleStatus = 'ongoing' | 'defended' | 'raided';

export interface RoundLog {
  round: number;
  at: string;
  attackerLosses: Record<string, number>;
  defenderLosses: Record<string, number>;
  attackerLeft: number;
  defenderLeft: number;
  // Armies that fought for the first time this round, with their bonus.
  joined?: { armyId: number; villageId: number; orders: string; units: Record<string, number>; bonus: number }[];
}

// What the ground gave the defenders of a field battle; at the Holy City,
// its guard (what is left of it).
export interface BattleSetup {
  ambush?: boolean;
  choke?: boolean;
  fort?: boolean;
  holyCity?: boolean;
  guard?: Record<string, number>;
}

// What a horde that won decided to do (see sim/horde.ts).
export interface BattleDecision {
  choice: 'raid' | 'raze';
  reasons: string[];
}

export interface Battle {
  id: number;
  worldId: number;
  waveId: number;
  // null: a field battle at (q, r).
  villageId: number | null;
  q: number;
  r: number;
  setup: BattleSetup;
  status: BattleStatus;
  round: number;
  attackerStance: Stance;
  attackerInitial: Units;
  defenderInitial: Units;
  rounds: RoundLog[];
  loot: Resources | null;
  decision: BattleDecision | null;
  startedAt: Date;
  endedAt: Date | null;
}

interface BattleRow {
  id: number;
  world_id: number;
  wave_id: number;
  village_id: number | null;
  q: number;
  r: number;
  setup: BattleSetup;
  status: BattleStatus;
  round: number;
  attacker_stance: Stance;
  attacker_initial: Units;
  defender_initial: Units;
  rounds: RoundLog[];
  loot: Resources | null;
  decision: BattleDecision | null;
  started_at: Date;
  ended_at: Date | null;
}

function fromRow(row: BattleRow): Battle {
  return {
    id: row.id,
    worldId: row.world_id,
    waveId: row.wave_id,
    villageId: row.village_id,
    q: row.q,
    r: row.r,
    setup: row.setup,
    status: row.status,
    round: row.round,
    attackerStance: row.attacker_stance,
    attackerInitial: row.attacker_initial,
    defenderInitial: row.defender_initial,
    rounds: row.rounds,
    loot: row.loot,
    decision: row.decision,
    startedAt: row.started_at,
    endedAt: row.ended_at,
  };
}

export async function insertBattle(
  client: DbClient,
  battle: Pick<Battle, 'worldId' | 'waveId' | 'villageId' | 'q' | 'r' | 'attackerStance' | 'attackerInitial' | 'defenderInitial' | 'startedAt'> &
    Partial<Pick<Battle, 'setup'>>,
): Promise<Battle> {
  const { rows } = await client.query<BattleRow>(
    `INSERT INTO battles (world_id, wave_id, village_id, q, r, setup, attacker_stance, attacker_initial, defender_initial, started_at)
     VALUES ($1, $2, $3, $8, $9, $10, $4, $5, $6, $7) RETURNING *`,
    [
      battle.worldId,
      battle.waveId,
      battle.villageId,
      battle.attackerStance,
      JSON.stringify(battle.attackerInitial),
      JSON.stringify(battle.defenderInitial),
      battle.startedAt,
      battle.q,
      battle.r,
      JSON.stringify(battle.setup ?? {}),
    ],
  );
  return fromRow(rows[0]!);
}

export async function loadBattle(client: DbClient, id: number): Promise<Battle> {
  const { rows } = await client.query<BattleRow>('SELECT * FROM battles WHERE id = $1', [id]);
  if (!rows[0]) throw new NotFoundError(`Battle ${id} not found`);
  return fromRow(rows[0]);
}

export async function recordRound(
  client: DbClient,
  id: number,
  log: RoundLog,
  end: { status: Exclude<BattleStatus, 'ongoing'>; at: Date; loot: Resources | null } | null,
): Promise<void> {
  await client.query(
    `UPDATE battles SET round = $2, rounds = rounds || $3::jsonb, status = $4, ended_at = $5, loot = $6 WHERE id = $1`,
    [
      id,
      log.round,
      JSON.stringify([log]),
      end?.status ?? 'ongoing',
      end?.at ?? null,
      end?.loot ? JSON.stringify(end.loot) : null,
    ],
  );
}

// Ongoing battles and the most recent finished ones, newest first.
export async function listRecentBattles(client: DbClient, worldId: number, limit = 10): Promise<Battle[]> {
  const { rows } = await client.query<BattleRow>(
    `SELECT * FROM battles WHERE world_id = $1
     ORDER BY (status = 'ongoing') DESC, started_at DESC, id DESC LIMIT $2`,
    [worldId, limit],
  );
  return rows.map(fromRow);
}

// An army joined: its troops count towards the defenders' starting strength.
export async function addDefenders(client: DbClient, id: number, units: Units): Promise<void> {
  const battle = await loadBattle(client, id);
  const sum: Record<string, number> = { ...battle.defenderInitial };
  for (const [unit, n] of Object.entries(units)) sum[unit] = (sum[unit] ?? 0) + n;
  await client.query('UPDATE battles SET defender_initial = $2 WHERE id = $1', [id, JSON.stringify(sum)]);
}

export async function setDecision(client: DbClient, id: number, decision: BattleDecision): Promise<void> {
  await client.query('UPDATE battles SET decision = $2 WHERE id = $1', [id, JSON.stringify(decision)]);
}

export async function saveSetup(client: DbClient, id: number, setup: BattleSetup): Promise<void> {
  await client.query('UPDATE battles SET setup = $2 WHERE id = $1', [id, JSON.stringify(setup)]);
}
