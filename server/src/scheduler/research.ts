// Research on the scheduler: research_complete marks the tech known and
// gives every one of the player's villages its effects.
import { z } from 'zod';
import { notifyWorld } from '../db/notify.js';
import { finishResearch, listResearch } from '../db/research.js';
import { listVillages, saveVillageState } from '../db/villages.js';
import { bonusesOf } from '../sim/research.js';
import { withBonuses } from '../sim/village.js';
import type { HandlerRegistry } from './events.js';
import { tell } from './notices.js';

export const researchPayload = z.object({ accountId: z.number().int(), tech: z.string() });
export type ResearchPayload = z.infer<typeof researchPayload>;

export const researchHandlers: HandlerRegistry = {
  async research_complete({ client, data, world }, event) {
    const { accountId, tech } = researchPayload.parse(event.payload);
    if (!(await finishResearch(client, world.id, accountId, tech))) return;
    const known = (await listResearch(client, world.id, accountId)).filter((r) => r.status === 'done').map((r) => r.tech);
    const bonuses = bonusesOf(data, known);
    for (const village of await listVillages(client, world.id)) {
      if (village.ownerAccountId !== accountId) continue;
      await saveVillageState(client, village.id, withBonuses(data, village.state, bonuses, event.dueAt, world.speed));
      await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
    }
    await notifyWorld(client, { worldId: world.id, type: 'research' });
    await tell(client, world, accountId, {
      kind: 'research_done',
      tier: 'digest',
      title: `${data.research.techs[tech]?.name ?? tech} researched`,
      body: data.research.techs[tech]?.description ?? '',
    }, event.dueAt);
  },
};
