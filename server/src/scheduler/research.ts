import { findBridge } from '../db/bridges.js';
import { bridgeBonuses } from '../sim/bridge.js';
// Research on the scheduler: research_complete marks the tech known and
// gives every village of the group its effects (research is shared).
import { clanBonuses } from '../sim/clans.js';
import { z } from 'zod';
import type { GameData } from '../data/index.js';
import type { DbClient } from '../db/pool.js';
import { listScrolls } from '../db/sites.js';
import { listMembers, type World } from '../db/worlds.js';
import { combine, rosterBonuses } from '../sim/heroes.js';
import { loreBonuses } from '../sim/sites.js';
import { notifyWorld } from '../db/notify.js';
import { finishResearch, listResearch, loadResearchPoints, saveResearchPoints } from '../db/research.js';
import { listVillages, saveVillageState } from '../db/villages.js';
import { bonusesOf, researchPointsAt } from '../sim/research.js';
import { researchPerHour, withBonuses } from '../sim/village.js';
import type { HandlerRegistry } from './events.js';
import { tell } from './notices.js';

export const researchPayload = z.object({ accountId: z.number().int(), tech: z.string() });
export type ResearchPayload = z.infer<typeof researchPayload>;

// Every tech the group knows (whoever started it).
export async function groupKnown(client: DbClient, worldId: number): Promise<string[]> {
  return [...new Set((await listResearch(client, worldId)).filter((r) => r.status === 'done').map((r) => r.tech))].sort();
}

// A player's bonuses: the group's research and lore scrolls, their clan
// and their roster hero.
export async function playerBonuses(client: DbClient, data: GameData, worldId: number, accountId: number): Promise<Record<string, number>> {
  const known = await groupKnown(client, worldId);
  const scrolls = (await listScrolls(client, worldId)).map((s) => s.scroll);
  const member = (await listMembers(client, worldId)).find((m) => m.accountId === accountId);
  const own = combine(clanBonuses(data, member?.clan ?? null), rosterBonuses(data, member?.heroKind ?? null));
  // The blessings of the bridge's finished stages, for everyone.
  const blessed = bridgeBonuses(data, await findBridge(client, worldId));
  return combine(combine(combine(bonusesOf(data, known), loreBonuses(data, scrolls)), blessed), own);
}

// Gives every village of `accountIds` its owner's current bonuses.
export async function refreshBonuses(client: DbClient, data: GameData, world: World, accountIds: readonly number[], at: Date): Promise<void> {
  for (const accountId of accountIds) {
    const bonuses = await playerBonuses(client, data, world.id, accountId);
    for (const village of await listVillages(client, world.id)) {
      if (village.ownerAccountId !== accountId) continue;
      await saveVillageState(client, village.id, withBonuses(data, village.state, bonuses, at, world.speed));
      await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
    }
  }
}

// Research per hour the player's Academies bring in, as their villages stand.
export async function researchRate(client: DbClient, data: GameData, world: World, accountId: number): Promise<number> {
  return (await listVillages(client, world.id))
    .filter((v) => v.ownerAccountId === accountId)
    .reduce((sum, v) => sum + researchPerHour(data, v.state.plots, world.speed), 0);
}

// Credits the player's research up to `at` at the rate their villages give
// now. Called before anything changes that rate, and before spending.
export async function settleResearchPoints(client: DbClient, data: GameData, world: World, accountId: number, at: Date): Promise<number> {
  const points = await loadResearchPoints(client, world.id, accountId);
  const amount = researchPointsAt(points, await researchRate(client, data, world, accountId), at);
  await saveResearchPoints(client, world.id, accountId, { amount, settledAt: at });
  return amount;
}

// The research the group's Academies have brought in, all together (each
// member's settled up to `at`).
export async function groupPoints(client: DbClient, data: GameData, world: World, at: Date): Promise<number> {
  let sum = 0;
  for (const member of await listMembers(client, world.id)) sum += await settleResearchPoints(client, data, world, member.accountId, at);
  return sum;
}

// Takes `amount` of research from the group's pool, from the members in
// turn (by account), each as far as they have; the pool must hold it.
export async function spendGroupPoints(client: DbClient, data: GameData, world: World, amount: number, at: Date): Promise<void> {
  let left = amount;
  const members = (await listMembers(client, world.id)).map((m) => m.accountId).sort((a, b) => a - b);
  for (const accountId of members) {
    if (left <= 0) break;
    const have = await settleResearchPoints(client, data, world, accountId, at);
    const take = Math.min(have, left);
    await saveResearchPoints(client, world.id, accountId, { amount: have - take, settledAt: at });
    left -= take;
  }
}

export const researchHandlers: HandlerRegistry = {
  async research_complete({ client, data, world }, event) {
    const { accountId, tech } = researchPayload.parse(event.payload);
    if (!(await finishResearch(client, world.id, accountId, tech))) return;
    // The group's: every member's villages take its effects.
    const members = (await listMembers(client, world.id)).map((m) => m.accountId);
    await refreshBonuses(client, data, world, members, event.dueAt);
    await notifyWorld(client, { worldId: world.id, type: 'research' });
    for (const member of members) {
      await tell(client, world, member, {
        kind: 'research_done',
        tier: 'digest',
        title: '{tech} researched',
        body: data.research.techs[tech]?.description ?? '',
        vars: { tech: data.research.techs[tech]?.name ?? tech },
      }, event.dueAt);
    }
  },
};
