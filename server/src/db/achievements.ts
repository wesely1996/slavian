// Achievements earned (data/achievements.json), per run and player.
import type { DbClient } from './pool.js';

export interface Earned {
  readonly accountId: number;
  readonly achievement: string;
  readonly earnedAt: Date;
}

// Records an achievement; false when the player already had it this run.
export async function insertAchievement(client: DbClient, worldId: number, accountId: number, achievement: string, at: Date): Promise<boolean> {
  const { rows } = await client.query(
    `INSERT INTO achievements (world_id, account_id, achievement, earned_at) VALUES ($1, $2, $3, $4)
     ON CONFLICT (world_id, account_id, achievement) DO NOTHING RETURNING id`,
    [worldId, accountId, achievement, at],
  );
  return rows.length > 0;
}

// A run's achievements, in the order they were earned.
export async function listAchievements(client: DbClient, worldId: number): Promise<Earned[]> {
  const { rows } = await client.query<{ account_id: string; achievement: string; earned_at: Date }>(
    'SELECT account_id, achievement, earned_at FROM achievements WHERE world_id = $1 ORDER BY id',
    [worldId],
  );
  return rows.map((r) => ({ accountId: Number(r.account_id), achievement: r.achievement, earnedAt: r.earned_at }));
}

// Every achievement a player has earned in any run: when first, and where.
export async function accountAchievements(client: DbClient, accountId: number): Promise<{ achievement: string; worldId: number; earnedAt: Date; times: number }[]> {
  const { rows } = await client.query<{ achievement: string; world_id: string; earned_at: Date; times: number }>(
    `SELECT DISTINCT ON (achievement) achievement, world_id, earned_at, count(*) OVER (PARTITION BY achievement)::int AS times
     FROM achievements WHERE account_id = $1 ORDER BY achievement, earned_at, id`,
    [accountId],
  );
  return rows.map((r) => ({ achievement: r.achievement, worldId: Number(r.world_id), earnedAt: r.earned_at, times: r.times }));
}
