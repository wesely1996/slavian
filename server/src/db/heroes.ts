import type { GameData, HeroSlot } from '../data/index.js';
import { NotFoundError } from '../errors.js';
import { combine, heroBonuses, newHero, type HeroState, type HeroStatus } from '../sim/heroes.js';
import type { Bonuses } from '../sim/research.js';
import type { PathStep } from '../sim/waves.js';
import type { DbClient } from './pool.js';

export interface Hero extends HeroState {
  worldId: number;
  accountId: number;
  status: HeroStatus;
  villageId: number | null;
  path: PathStep[] | null;
  departsAt: Date | null;
  arrivesAt: Date | null;
  woundedUntil: Date | null;
}

interface HeroRow {
  world_id: number;
  account_id: number;
  name: string;
  status: HeroStatus;
  village_id: number | null;
  level: number;
  xp: number;
  skill_points: number;
  skills: Record<string, number>;
  gear: Partial<Record<HeroSlot, string>>;
  inventory: string[];
  path: PathStep[] | null;
  departs_at: Date | null;
  arrives_at: Date | null;
  wounded_until: Date | null;
}

function fromRow(row: HeroRow): Hero {
  return {
    worldId: row.world_id,
    accountId: row.account_id,
    name: row.name,
    status: row.status,
    villageId: row.village_id,
    level: row.level,
    xp: row.xp,
    skillPoints: row.skill_points,
    skills: row.skills,
    gear: row.gear,
    inventory: row.inventory,
    path: row.path,
    departsAt: row.departs_at,
    arrivesAt: row.arrives_at,
    woundedUntil: row.wounded_until,
  };
}

// Gives every member with a village a hero, standing in their first one.
export async function ensureHeroes(client: DbClient, data: GameData, worldId: number, seed: number): Promise<number> {
  const { rows } = await client.query<{ account_id: number; village_id: number }>(
    `SELECT DISTINCT ON (v.owner_account_id) v.owner_account_id AS account_id, v.id AS village_id
     FROM villages v
     WHERE v.world_id = $1 AND v.owner_account_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM heroes h WHERE h.world_id = v.world_id AND h.account_id = v.owner_account_id)
     ORDER BY v.owner_account_id, v.id`,
    [worldId],
  );
  for (const row of rows) {
    const hero = newHero(data, seed, row.account_id);
    await client.query(
      'INSERT INTO heroes (world_id, account_id, name, village_id) VALUES ($1, $2, $3, $4) ON CONFLICT DO NOTHING',
      [worldId, row.account_id, hero.name, row.village_id],
    );
  }
  return rows.length;
}

export async function loadHero(client: DbClient, worldId: number, accountId: number): Promise<Hero> {
  const { rows } = await client.query<HeroRow>('SELECT * FROM heroes WHERE world_id = $1 AND account_id = $2', [
    worldId,
    accountId,
  ]);
  if (!rows[0]) throw new NotFoundError('You have no hero in this world');
  return fromRow(rows[0]);
}

// The hero standing (not wounded) in a village, if any.
export async function heroAt(client: DbClient, villageId: number): Promise<Hero | null> {
  const { rows } = await client.query<HeroRow>(`SELECT * FROM heroes WHERE village_id = $1 AND status = 'home'`, [villageId]);
  return rows[0] ? fromRow(rows[0]) : null;
}

export async function listHeroes(client: DbClient, worldId: number): Promise<Hero[]> {
  const { rows } = await client.query<HeroRow>('SELECT * FROM heroes WHERE world_id = $1 ORDER BY account_id', [worldId]);
  return rows.map(fromRow);
}

export async function saveHero(client: DbClient, hero: Hero): Promise<void> {
  await client.query(
    `UPDATE heroes SET name = $3, status = $4, village_id = $5, level = $6, xp = $7, skill_points = $8, skills = $9,
       gear = $10, inventory = $11, path = $12, departs_at = $13, arrives_at = $14, wounded_until = $15
     WHERE world_id = $1 AND account_id = $2`,
    [
      hero.worldId,
      hero.accountId,
      hero.name,
      hero.status,
      hero.villageId,
      hero.level,
      hero.xp,
      hero.skillPoints,
      JSON.stringify(hero.skills),
      JSON.stringify(hero.gear),
      JSON.stringify(hero.inventory),
      hero.path ? JSON.stringify(hero.path) : null,
      hero.departsAt,
      hero.arrivesAt,
      hero.woundedUntil,
    ],
  );
}

// The effects that count for a village: its owner's research, plus the
// hero standing in it.
export async function effectiveBonuses(
  client: DbClient,
  data: GameData,
  village: { id: number; state: { bonuses: Bonuses } },
): Promise<Record<string, number>> {
  const hero = await heroAt(client, village.id);
  return hero ? combine(village.state.bonuses, heroBonuses(data, hero)) : { ...village.state.bonuses };
}
