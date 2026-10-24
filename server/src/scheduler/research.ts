// Research on the scheduler: research_complete marks the tech known and
// gives every one of the player's villages its effects.
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

// A player's bonuses: their research, the group's lore scrolls, their clan
// and their roster hero.
export async function playerBonuses(client: DbClient, data: GameData, worldId: number, accountId: number): Promise<Record<string, number>> {
  const known = (await listResearch(client, worldId, accountId)).filter((r) => r.status === 'done').map((r) => r.tech);
  const scrolls = (await listScrolls(client, worldId)).map((s) => s.scroll);
  const member = (await listMembers(client, worldId)).find((m) => m.accountId === accountId);
  const own = combine(clanBonuses(data, member?.clan ?? null), rosterBonuses(data, member?.heroKind ?? null));
  return combine(combine(bonusesOf(data, known), loreBonuses(data, scrolls)), own);
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

export const researchHandlers: HandlerRegistry = {
  async research_complete({ client, data, world }, event) {
    const { accountId, tech } = researchPayload.parse(event.payload);
    if (!(await finishResearch(client, world.id, accountId, tech))) return;
    await refreshBonuses(client, data, world, [accountId], event.dueAt);
    await notifyWorld(client, { worldId: world.id, type: 'research' });
    await tell(client, world, accountId, {
      kind: 'research_done',
      tier: 'digest',
      title: '{tech} researched',
      body: data.research.techs[tech]?.description ?? '',
      vars: { tech: data.research.techs[tech]?.name ?? tech },
    }, event.dueAt);
  },
};
