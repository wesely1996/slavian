import { z } from 'zod';
import { notifyWorld } from '../db/notify.js';
import { loadVillage, saveVillageState } from '../db/villages.js';
import { completeBuild, completeTraining } from '../sim/village.js';
import type { HandlerRegistry } from './events.js';
import { battleHandlers } from './battles.js';
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
    const plot = payload.plot ?? village.state.queue[0]?.plot ?? '';
    const state = completeBuild(data, village.state, plot, payload.targetLevel, event.dueAt, world.speed);
    await saveVillageState(client, village.id, state);
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
};
