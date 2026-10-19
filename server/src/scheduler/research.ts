// Research on the scheduler: research_complete marks the tech known and
// gives every one of the player's villages its effects.
import { z } from 'zod';
import type { GameData } from '../data/index.js';
import type { DbClient } from '../db/pool.js';
import { listScrolls } from '../db/sites.js';
import type { World } from '../db/worlds.js';
import { combine } from '../sim/heroes.js';
import { loreBonuses } from '../sim/sites.js';
import { notifyWorld } from '../db/notify.js';
import { finishResearch, listResearch } from '../db/research.js';
import { listVillages, saveVillageState } from '../db/villages.js';
import { bonusesOf } from '../sim/research.js';
import { withBonuses } from '../sim/village.js';
import type { HandlerRegistry } from './events.js';
import { tell } from './notices.js';

export const researchPayload = z.object({ accountId: z.number().int(), tech: z.string() });
export type ResearchPayload = z.infer<typeof researchPayload>;

// A player's bonuses: their research plus the group's lore scrolls.
export async function playerBonuses(client: DbClient, data: GameData, worldId: number, accountId: number): Promise<Record<string, number>> {
  const known = (await listResearch(client, worldId, accountId)).filter((r) => r.status === 'done').map((r) => r.tech);
  const scrolls = (await listScrolls(client, worldId)).map((s) => s.scroll);
  return combine(bonusesOf(data, known), loreBonuses(data, scrolls));
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

export const researchHandlers: HandlerRegistry = {
  async research_complete({ client, data, world }, event) {
    const { accountId, tech } = researchPayload.parse(event.payload);
    if (!(await finishResearch(client, world.id, accountId, tech))) return;
    await refreshBonuses(client, data, world, [accountId], event.dueAt);
    await notifyWorld(client, { worldId: world.id, type: 'research' });
    await tell(client, world, accountId, {
      kind: 'research_done',
      tier: 'digest',
      title: `${data.research.techs[tech]?.name ?? tech} researched`,
      body: data.research.techs[tech]?.description ?? '',
    }, event.dueAt);
  },
};
