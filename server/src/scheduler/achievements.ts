// Achievements (data/achievements.json): earned once per player per run,
// where the game's moments happen, and told with a push notice.
import type { Achievement, GameData } from '../data/index.js';
import { hasAchievement, insertAchievement } from '../db/achievements.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { listMembers, type World } from '../db/worlds.js';
import { tell } from './notices.js';

// Achievements belong to the account: each run it comes up in is recorded,
// but the player is told only the first time ever.
export async function achieve(client: DbClient, data: GameData, world: World, accountId: number | null, achievement: Achievement, at: Date): Promise<void> {
  if (accountId === null) return;
  const before = await hasAchievement(client, accountId, achievement);
  if (!(await insertAchievement(client, world.id, accountId, achievement, at)) || before) return;
  const def = data.achievements.achievements[achievement];
  await tell(client, world, accountId, { kind: 'achievement', tier: 'push', title: 'Achievement: {name}', body: '{description}', vars: { name: def.name, description: def.description } }, at);
  await notifyWorld(client, { worldId: world.id, type: 'world' });
}

// For every member of the run.
export async function achieveAll(client: DbClient, data: GameData, world: World, achievement: Achievement, at: Date): Promise<void> {
  for (const member of await listMembers(client, world.id)) await achieve(client, data, world, member.accountId, achievement, at);
}
