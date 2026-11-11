import type { Front } from '../sim/mapgen.js';
import { NotFoundError } from '../errors.js';
import type { Stance } from '../data/index.js';
import type { ArmyOrders } from '../sim/armies.js';
import type { Resources } from '../sim/resources.js';
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
  // The general leading it.
  generalId: number | null;
  orders: ArmyOrders;
  // Its own battle stance.
  stance: Stance;
  units: Record<string, number>;
  status: ArmyStatus;
  // What it had when it joined its battle (it breaks on its losses since).
  engagedUnits: Record<string, number> | null;
  // Carried home from a cleared camp.
  loot: Resources | null;
  battleId: number | null;
  joinsRound: number | null;
  joinBonus: number;
  path: PathStep[];
  departsAt: Date;
  arrivesAt: Date;
  leavesAt: Date | null;
  returnsAt: Date | null;
  // Grain carried at supplyAt (null: an army from before supplies, fed by
  // its home village), when the food ran out, and the next hunger check.
  supply: number | null;
  supplyAt: Date | null;
  hungrySince: Date | null;
  hungerAt: Date | null;
  // When its wagons stand ready in a ring, a wagon fort (null: none).
  wagonFortAt: Date | null;
  // It comes home by itself once its errand is done.
  returnHome: boolean;
  // A raid beyond the map's edge (orders 'raid'; null otherwise).
  raid: ArmyRaid | null;
  // Quartered in a settlement, fort or supply point: fed by it since then
  // (null: it eats its own grain; sim/quarters.ts).
  quarteredAt: Date | null;
  // It answers battles nearby (data/armies.json respond.range).
  respond: boolean;
  // Where it stood when it went to answer a battle: it goes back after.
  post: ArmyPost | null;
}

export interface ArmyPost {
  q: number;
  r: number;
  // A settlement it stood in (null: a hex).
  villageId: number | null;
}

export interface RaidBattleEntry {
  stage: number;
  name: string;
  stronghold: boolean;
  won: boolean;
  battleId: number;
  kills: number;
  lost: number;
}

export interface ArmyRaid {
  front: Front;
  // Field battles before the stronghold.
  depth: number;
  // Stages fought so far.
  stage: number;
  battles: RaidBattleEntry[];
  // Rare finds it took (the North): what they were, as told.
  finds: string[];
  // A strike on a gathering horde (that wave's id): one battle at its
  // encampment, then home.
  waveId?: number;
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
  general_id: number | null;
  orders: ArmyOrders;
  stance: Stance;
  units: Record<string, number>;
  status: ArmyStatus;
  engaged_units: Record<string, number> | null;
  loot: Resources | null;
  battle_id: number | null;
  joins_round: number | null;
  join_bonus: number;
  path: PathStep[];
  departs_at: Date;
  arrives_at: Date;
  leaves_at: Date | null;
  returns_at: Date | null;
  supply: number | null;
  supply_at: Date | null;
  hungry_since: Date | null;
  hunger_at: Date | null;
  wagon_fort_at: Date | null;
  return_home: boolean;
  raid: ArmyRaid | null;
  quartered_at: Date | null;
  respond: boolean | null;
  post: ArmyPost | null;
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
    generalId: row.general_id === null ? null : Number(row.general_id),
    orders: row.orders,
    stance: row.stance,
    units: row.units,
    status: row.status,
    engagedUnits: row.engaged_units,
    loot: row.loot,
    battleId: row.battle_id,
    joinsRound: row.joins_round,
    joinBonus: Number(row.join_bonus),
    path: row.path,
    departsAt: row.departs_at,
    arrivesAt: row.arrives_at,
    leavesAt: row.leaves_at,
    returnsAt: row.returns_at,
    supply: row.supply === null ? null : Number(row.supply),
    supplyAt: row.supply_at,
    hungrySince: row.hungry_since,
    hungerAt: row.hunger_at,
    wagonFortAt: row.wagon_fort_at,
    returnHome: row.return_home ?? false,
    raid: row.raid ?? null,
    quarteredAt: row.quartered_at ?? null,
    respond: row.respond ?? true,
    post: row.post ?? null,
  };
}

export async function insertArmy(
  client: DbClient,
  a: Pick<
    Army,
    'worldId' | 'ownerAccountId' | 'homeVillageId' | 'targetVillageId' | 'targetQ' | 'targetR' | 'heroAccountId' | 'orders' | 'units' | 'path' | 'departsAt' | 'arrivesAt'
  > & {
      generalId?: number | null;
      supply?: number | null;
      supplyAt?: Date | null;
      stance?: Stance;
      returnHome?: boolean;
      raid?: ArmyRaid | null;
      quarteredAt?: Date | null;
      respond?: boolean;
    },
): Promise<Army> {
  const { rows } = await client.query<ArmyRow>(
    `INSERT INTO armies (world_id, owner_account_id, home_village_id, target_village_id, orders, units, path, departs_at, arrives_at,
       target_q, target_r, hero_account_id, general_id, supply, supply_at, stance, return_home, raid, quartered_at, respond)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20) RETURNING *`,
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
      a.generalId ?? null,
      a.supply ?? null,
      a.supplyAt ?? null,
      a.stance ?? 'balanced',
      a.returnHome ?? false,
      a.raid ? JSON.stringify(a.raid) : null,
      a.quarteredAt ?? null,
      a.respond ?? true,
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
    `UPDATE armies SET units = $2, status = $3, battle_id = $4, joins_round = $5, join_bonus = $6, leaves_at = $7, returns_at = $8, loot = $9,
       orders = $10, target_village_id = $11, target_q = $12, target_r = $13, path = $14, departs_at = $15, arrives_at = $16,
       supply = $17, supply_at = $18, hungry_since = $19, hunger_at = $20, wagon_fort_at = $21, stance = $22, engaged_units = $23,
       return_home = $24, raid = $25, home_village_id = $26, quartered_at = $27, respond = $28, post = $29
     WHERE id = $1`,
    [
      a.id,
      JSON.stringify(a.units),
      a.status,
      a.battleId,
      a.joinsRound,
      a.joinBonus,
      a.leavesAt,
      a.returnsAt,
      a.loot ? JSON.stringify(a.loot) : null,
      a.orders,
      a.targetVillageId,
      a.targetQ,
      a.targetR,
      JSON.stringify(a.path),
      a.departsAt,
      a.arrivesAt,
      a.supply,
      a.supplyAt,
      a.hungrySince,
      a.hungerAt,
      a.wagonFortAt,
      a.stance,
      a.engagedUnits ? JSON.stringify(a.engagedUnits) : null,
      a.returnHome,
      a.raid ? JSON.stringify(a.raid) : null,
      a.homeVillageId,
      a.quarteredAt,
      a.respond,
      a.post ? JSON.stringify(a.post) : null,
    ],
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
// Armies out on the map carrying their own grain (not done), oldest first.
export async function fieldArmies(client: DbClient, worldId: number): Promise<Army[]> {
  const { rows } = await client.query<ArmyRow>(`SELECT * FROM armies WHERE world_id = $1 AND status <> 'done' AND supply IS NOT NULL ORDER BY id`, [worldId]);
  return rows.map(fromRow);
}

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

// Who leads an army (the heroes' and generals' own rows say where they are).
export async function setArmyLeaders(client: DbClient, armyId: number, heroAccountId: number | null, generalId: number | null): Promise<void> {
  await client.query('UPDATE armies SET hero_account_id = $2, general_id = $3 WHERE id = $1', [armyId, heroAccountId, generalId]);
}
