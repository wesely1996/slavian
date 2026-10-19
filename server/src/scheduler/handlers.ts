import { z } from 'zod';
import { notifyWorld } from '../db/notify.js';
import { loadVillage, saveVillageState } from '../db/villages.js';
import { completeBuild, completeTraining, outpostHex } from '../sim/village.js';
import type { HandlerRegistry } from './events.js';
import { armyHandlers } from './armies.js';
import { battleHandlers } from './battles.js';
import { caravanHandlers } from './caravans.js';
import { expeditionHandlers } from './expeditions.js';
import { fieldHandlers } from './field.js';
import { hordeHandlers } from './horde.js';
import { campHandlers } from './camps.js';
import { siteHandlers } from './sites.js';
import { heroHandlers } from './heroes.js';
import { noticeHandlers } from './notices.js';
import { orderHandlers } from './orders.js';
import { researchHandlers } from './research.js';
import { outpostHandlers, outpostStanding } from './outposts.js';
import { tell } from './notices.js';
import { scoutingHandlers } from './scouting.js';
import { waveHandlers } from './waves.js';

export const buildCompletePayload = z.object({
  villageId: z.number().int(),
  // Older events have no plot; the queue head for the building is used.
  plot: z.string().optional(),
  building: z.string(),
  targetLevel: z.number().int().positive(),
});
export type BuildCompletePayload = z.infer<typeof buildCompletePayload>;

export const trainingCompletePayload = z.object({ villageId: z.number().int() });
export type TrainingCompletePayload = z.infer<typeof trainingCompletePayload>;

export const handlers: HandlerRegistry = {
  async build_complete({ client, data, world }, event) {
    const payload = buildCompletePayload.parse(event.payload);
    const village = await loadVillage(client, payload.villageId);
    // Razed before it was finished.
    if (village.ruin) return;
    const plot = payload.plot ?? village.state.queue[0]?.plot ?? '';
    const state = completeBuild(data, village.state, plot, payload.targetLevel, event.dueAt, world.speed);
    await saveVillageState(client, village.id, state);
    const def = data.buildings.buildings[payload.building];
    const big = payload.building === 'elder_hall' || payload.targetLevel >= data.notifications.bigBuildLevel;
    await tell(client, world, village.ownerAccountId, {
      kind: 'build_done',
      tier: big ? 'push' : 'digest',
      title: `${def?.name ?? payload.building} level ${payload.targetLevel} in ${village.name}`,
      body: big ? 'Finished. Your build queue may have room for more.' : 'Finished.',
    }, event.dueAt);
    const cell = outpostHex(plot);
    if (cell && payload.targetLevel === 1) {
      await outpostStanding(client, data, world, { villageId: village.id, plot, cell }, event.dueAt);
    }
    await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
  },

  // A batch finished: move its units into the garrison.
  async training_complete({ client, world }, event) {
    const payload = trainingCompletePayload.parse(event.payload);
    const village = await loadVillage(client, payload.villageId);
    await saveVillageState(client, village.id, completeTraining(village.state, event.dueAt));
    await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
  },

  ...waveHandlers,
  ...scoutingHandlers,
  ...battleHandlers,
  ...outpostHandlers,
  ...caravanHandlers,
  ...expeditionHandlers,
  ...researchHandlers,
  ...heroHandlers,
  ...orderHandlers,
  ...noticeHandlers,
  ...armyHandlers,
  ...fieldHandlers,
  ...hordeHandlers,
  ...campHandlers,
  ...siteHandlers,
};
