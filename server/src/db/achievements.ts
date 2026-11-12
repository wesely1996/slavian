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

// Whether the player has earned it before, in any run (solo ones sent).
export async function hasAchievement(client: DbClient, accountId: number, achievement: string): Promise<boolean> {
  const { rows } = await client.query(
    `SELECT 1 FROM achievements WHERE account_id = $1 AND achievement = $2
     UNION ALL SELECT 1 FROM solo_achievements WHERE account_id = $1 AND achievement = $2 LIMIT 1`,
    [accountId, achievement],
  );
  return rows.length > 0;
}

// Every achievement a player has earned in any run, solo ones included:
// when first, and how many runs it came up in.
export async function accountAchievements(client: DbClient, accountId: number): Promise<{ achievement: string; earnedAt: Date; times: number }[]> {
  const { rows } = await client.query<{ achievement: string; earned_at: Date; times: number }>(
    `SELECT achievement, min(earned_at) AS earned_at, sum(times)::int AS times FROM (
       SELECT achievement, min(earned_at) AS earned_at, count(*)::int AS times FROM achievements WHERE account_id = $1 GROUP BY achievement
       UNION ALL SELECT achievement, earned_at, runs FROM solo_achievements WHERE account_id = $1
     ) e GROUP BY achievement ORDER BY min(earned_at), achievement`,
    [accountId],
  );
  return rows.map((r) => ({ achievement: r.achievement, earnedAt: r.earned_at, times: r.times }));
}

// Solo achievements sent from the device: the earliest time wins, and the
// most runs.
export async function recordSoloAchievements(client: DbClient, accountId: number, earned: readonly { achievement: string; earnedAt: Date; runs: number }[]): Promise<void> {
  for (const e of earned) {
    await client.query(
      `INSERT INTO solo_achievements (account_id, achievement, earned_at, runs) VALUES ($1, $2, $3, $4)
       ON CONFLICT (account_id, achievement) DO UPDATE
       SET earned_at = LEAST(solo_achievements.earned_at, EXCLUDED.earned_at), runs = GREATEST(solo_achievements.runs, EXCLUDED.runs)`,
      [accountId, e.achievement, e.earnedAt, e.runs],
    );
  }
}
