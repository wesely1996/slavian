// What daily map events bring (data/events.json reward, failure): a bounty
// for whoever does one, to their first village; and for one left undone,
// the next horde of its front hating the more. Told as event notices, which
// the game shows in a popup.
import type { GameData } from '../data/index.js';
import type { DbClient } from '../db/pool.js';
import { listVillages } from '../db/villages.js';
import { listMembers, type World } from '../db/worlds.js';
import { eventBounty } from '../sim/events.js';
import type { Front } from '../sim/mapgen.js';
import { total } from '../sim/battle.js';
import type { Resources } from '../sim/resources.js';
import { tell } from './notices.js';
import { reward } from './onboarding.js';
import { angerHorde } from './waves.js';

const MS_PER_HOUR = 3_600_000;

// The day of the run `at` falls on (the first event's is 1).
export function eventDay(data: GameData, world: World, at: Date): number {
  if (!world.startedAt) return 1;
  const every = Math.round((data.events.everyHours * MS_PER_HOUR) / world.speed);
  return Math.max(1, Math.floor((at.getTime() - world.startedAt.getTime()) / every));
}

// The bounty an event done at `at` brings.
export function bountyAt(data: GameData, world: World, at: Date): Resources {
  return eventBounty(data, eventDay(data, world, at));
}

// The bounty, to the player's first standing village, and the notice of it.
export async function rewardEvent(
  client: DbClient,
  data: GameData,
  world: World,
  accountId: number | null,
  notice: { title: string; body?: string; vars: Record<string, string | number> },
  at: Date,
): Promise<void> {
  if (accountId === null) return;
  const bounty = bountyAt(data, world, at);
  const home = (await listVillages(client, world.id)).filter((v) => v.ownerAccountId === accountId && !v.ruin).sort((a, b) => a.id - b.id)[0];
  if (home) await reward(client, world, accountId, bounty, at);
  await tell(client, world, accountId, {
    kind: 'event',
    tier: 'push',
    title: notice.title,
    body: home ? (notice.body ?? 'Bounty for {village}: {wood} wood, {stone} stone, {grain} grain and {iron} iron.') : 'Done, with no village left to take the bounty.',
    vars: { ...notice.vars, village: home?.name ?? '', ...bounty },
  }, at);
}

// Left undone: the next horde of the front hates the more, and everyone is told.
export async function failEvent(client: DbClient, data: GameData, world: World, front: Front, title: string, vars: Record<string, string | number>, at: Date): Promise<void> {
  const { rows } = await client.query<{ id: number; hatred: number }>(
    `SELECT id, hatred FROM waves WHERE world_id = $1 AND front = $2 AND status = 'scheduled' AND band_of IS NULL ORDER BY spawn_at, id LIMIT 1`,
    [world.id, front],
  );
  const wave = rows[0];
  const amount = data.events.failure.hatred;
  if (wave && amount > 0) await angerHorde(client, data, world, wave.id, amount, at);
  for (const member of await listMembers(client, world.id)) {
    await tell(client, world, member.accountId, {
      kind: 'event',
      tier: 'push',
      title,
      body: wave && amount > 0 ? 'The next horde from the {front} hates you the more for it: +{hatred}% attack and defense.' : 'Nothing more came of it.',
      vars: { ...vars, front, hatred: wave ? Math.round((Number(wave.hatred) + amount) * 100) : 0 },
    }, at);
  }
}

// "1400 resources", for a notice telling of the bounty to come.
export function bountyTotal(data: GameData, world: World, at: Date): number {
  return total(bountyAt(data, world, at));
}
