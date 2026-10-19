import type { DbClient } from './pool.js';
import type { World } from './worlds.js';

// How a finished run went, for the win and loss screens.
export interface RunSummary {
  outcome: 'won' | 'lost';
  days: number;
  wavesBeaten: number;
  wavesFaced: number;
  battlesWon: number;
  campsCleared: number;
  sitesExplored: number;
  scrolls: number;
  villagesFounded: number;
  villagesLost: number;
  members: { accountId: number; displayName: string; villages: number; villagesLost: number }[];
}

async function count(client: DbClient, sql: string, worldId: number): Promise<number> {
  const { rows } = await client.query<{ n: number }>(sql, [worldId]);
  return rows[0]!.n;
}

export async function runSummary(client: DbClient, world: World): Promise<RunSummary | null> {
  if ((world.status !== 'won' && world.status !== 'lost') || !world.startedAt) return null;
  const end = world.endedAt ?? world.startedAt;
  const { rows: members } = await client.query<{ accountId: number; displayName: string; villages: number; villagesLost: number }>(
    `SELECT m.account_id::int AS "accountId", a.display_name AS "displayName",
       count(v.id) FILTER (WHERE NOT v.refuge)::int AS villages,
       count(v.id) FILTER (WHERE v.ruin IS NOT NULL)::int AS "villagesLost"
     FROM world_members m JOIN accounts a ON a.id = m.account_id
     LEFT JOIN villages v ON v.world_id = m.world_id AND v.owner_account_id = m.account_id
     WHERE m.world_id = $1
     GROUP BY m.account_id, a.display_name, m.joined_at
     ORDER BY m.joined_at, m.account_id`,
    [world.id],
  );
  return {
    outcome: world.status,
    days: Math.round(((end.getTime() - world.startedAt.getTime()) * world.speed) / 86_400_000 * 10) / 10,
    wavesBeaten: await count(client, "SELECT count(*)::int AS n FROM waves WHERE world_id = $1 AND status = 'defeated'", world.id),
    wavesFaced: await count(client, "SELECT count(*)::int AS n FROM waves WHERE world_id = $1 AND spawn_q IS NOT NULL", world.id),
    battlesWon: await count(client, "SELECT count(*)::int AS n FROM battles WHERE world_id = $1 AND status IN ('defended', 'cleared', 'repelled')", world.id),
    campsCleared: await count(client, "SELECT count(*)::int AS n FROM camps WHERE world_id = $1 AND status = 'cleared'", world.id),
    sitesExplored: await count(client, "SELECT count(*)::int AS n FROM sites WHERE world_id = $1 AND status = 'explored'", world.id),
    scrolls: await count(client, 'SELECT count(*)::int AS n FROM lore WHERE world_id = $1', world.id),
    villagesFounded: members.reduce((n, m) => n + m.villages, 0),
    villagesLost: members.reduce((n, m) => n + m.villagesLost, 0),
    members,
  };
}
