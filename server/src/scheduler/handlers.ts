import { z } from 'zod';
import { notifyWorld } from '../db/notify.js';
import { loadVillage, saveVillageState } from '../db/villages.js';
import { completeBuild } from '../sim/village.js';
import type { HandlerRegistry } from './events.js';

export const buildCompletePayload = z.object({
  villageId: z.number().int(),
  building: z.string(),
  targetLevel: z.number().int().positive(),
});
export type BuildCompletePayload = z.infer<typeof buildCompletePayload>;

export const handlers: HandlerRegistry = {
  async build_complete({ client, data, world }, event) {
    const payload = buildCompletePayload.parse(event.payload);
    const village = await loadVillage(client, payload.villageId);
    const state = completeBuild(data, village.state, payload.building, payload.targetLevel, event.dueAt, world.speed);
    await saveVillageState(client, village.id, state);
    await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
  },
};
