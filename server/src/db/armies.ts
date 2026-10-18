import { NotFoundError } from '../errors.js';
import type { ArmyOrders } from '../sim/armies.js';
import type { PathStep } from '../sim/waves.js';
import type { DbClient } from './pool.js';

export type ArmyStatus = 'marching' | 'stationed' | 'engaged' | 'returning' | 'done';

export interface Army {
  id: number;
  worldId: number;
  ownerAccountId: number | null;
  homeVillageId: number;
  // null: holding the hex (targetQ, targetR).
  targetVillageId: number | null;
  targetQ: number;
  targetR: number;
  heroAccountId: number | null;
  orders: ArmyOrders;
  units: Record<string, number>;
  status: ArmyStatus;
  battleId: number | null;
  joinsRound: number | null;
  joinBonus: number;
  path: PathStep[];
  departsAt: Date;
  arrivesAt: Date;
  leavesAt: Date | null;
  returnsAt: Date | null;
}

interface ArmyRow {
  id: number;
  world_id: number;
  owner_account_id: number | null;
  home_village_id: number;
  target_village_id: number | null;
  target_q: number;
  target_r: number;
  hero_account_id: number | null;
  orders: ArmyOrders;
  units: Record<string, number>;
  status: ArmyStatus;
  battle_id: number | null;
  joins_round: number | null;
  join_bonus: number;
  path: PathStep[];
  departs_at: Date;
  arrives_at: Date;
  leaves_at: Date | null;
  returns_at: Date | null;
}

function fromRow(row: ArmyRow): Army {
  return {
    id: row.id,
    worldId: row.world_id,
    ownerAccountId: row.owner_account_id,
    homeVillageId: row.home_village_id,
    targetVillageId: row.target_village_id,
    targetQ: row.target_q,
    targetR: row.target_r,
    heroAccountId: row.hero_account_id,
    orders: row.orders,
    units: row.units,
    status: row.status,
    battleId: row.battle_id,
    joinsRound: row.joins_round,
    joinBonus: Number(row.join_bonus),
    path: row.path,
    departsAt: row.departs_at,
    arrivesAt: row.arrives_at,
    leavesAt: row.leaves_at,
    returnsAt: row.returns_at,
  };
}

export async function insertArmy(
  client: DbClient,
  a: Pick<
    Army,
    'worldId' | 'ownerAccountId' | 'homeVillageId' | 'targetVillageId' | 'targetQ' | 'targetR' | 'heroAccountId' | 'orders' | 'units' | 'path' | 'departsAt' | 'arrivesAt'
  >,
): Promise<Army> {
  const { rows } = await client.query<ArmyRow>(
    `INSERT INTO armies (world_id, owner_account_id, home_village_id, target_village_id, orders, units, path, departs_at, arrives_at,
       target_q, target_r, hero_account_id)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12) RETURNING *`,
    [
      a.worldId,
      a.ownerAccountId,
      a.homeVillageId,
      a.targetVillageId,
      a.orders,
      JSON.stringify(a.units),
      JSON.stringify(a.path),
      a.departsAt,
      a.arrivesAt,
      a.targetQ,
      a.targetR,
      a.heroAccountId,
    ],
  );
  return fromRow(rows[0]!);
}

export async function loadArmy(client: DbClient, id: number): Promise<Army> {
  const { rows } = await client.query<ArmyRow>('SELECT * FROM armies WHERE id = $1', [id]);
  if (!rows[0]) throw new NotFoundError(`Army ${id} not found`);
  return fromRow(rows[0]);
}

export async function saveArmy(client: DbClient, a: Army): Promise<void> {
  await client.query(
    `UPDATE armies SET units = $2, status = $3, battle_id = $4, joins_round = $5, join_bonus = $6, leaves_at = $7, returns_at = $8
     WHERE id = $1`,
    [a.id, JSON.stringify(a.units), a.status, a.battleId, a.joinsRound, a.joinBonus, a.leavesAt, a.returnsAt],
  );
}

// Armies standing at a village (support) or fighting in its battle.
export async function armiesAt(client: DbClient, villageId: number, status: ArmyStatus[]): Promise<Army[]> {
  const { rows } = await client.query<ArmyRow>(
    'SELECT * FROM armies WHERE target_village_id = $1 AND status = ANY($2) ORDER BY id',
    [villageId, status],
  );
  return rows.map(fromRow);
}

// Armies holding a hex (not at a village).
export async function armiesHolding(client: DbClient, worldId: number, q: number, r: number, status: ArmyStatus[]): Promise<Army[]> {
  const { rows } = await client.query<ArmyRow>(
    `SELECT * FROM armies WHERE world_id = $1 AND target_q = $2 AND target_r = $3 AND target_village_id IS NULL
       AND status = ANY($4) ORDER BY id`,
    [worldId, q, r, status],
  );
  return rows.map(fromRow);
}

export async function armiesInBattle(client: DbClient, battleId: number): Promise<Army[]> {
  const { rows } = await client.query<ArmyRow>(`SELECT * FROM armies WHERE battle_id = $1 AND status = 'engaged' ORDER BY id`, [battleId]);
  return rows.map(fromRow);
}

// On the road or abroad, plus the latest few that came home.
export async function listArmies(client: DbClient, worldId: number, recent = 5): Promise<Army[]> {
  const { rows } = await client.query<ArmyRow>(
    `(SELECT * FROM armies WHERE world_id = $1 AND status <> 'done')
     UNION ALL
     (SELECT * FROM armies WHERE world_id = $1 AND status = 'done' ORDER BY COALESCE(returns_at, arrives_at) DESC LIMIT $2)
     ORDER BY departs_at DESC, id DESC`,
    [worldId, recent],
  );
  return rows.map(fromRow);
}

export interface ReinforceRule {
  share: number;
  range: number;
}

export async function loadReinforceRule(client: DbClient, villageId: number): Promise<ReinforceRule> {
  const { rows } = await client.query<{ reinforce_share: number; reinforce_range: number }>(
    'SELECT reinforce_share, reinforce_range FROM villages WHERE id = $1',
    [villageId],
  );
  if (!rows[0]) throw new NotFoundError(`Village ${villageId} not found`);
  return { share: Number(rows[0].reinforce_share), range: rows[0].reinforce_range };
}

export async function saveReinforceRule(client: DbClient, villageId: number, rule: ReinforceRule): Promise<void> {
  await client.query('UPDATE villages SET reinforce_share = $2, reinforce_range = $3 WHERE id = $1', [villageId, rule.share, rule.range]);
}
