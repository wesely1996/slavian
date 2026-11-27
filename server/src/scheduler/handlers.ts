import { z } from 'zod';
import { notifyWorld } from '../db/notify.js';
import { loadVillage, saveVillageState } from '../db/villages.js';
import { completeBuild, completeTraining, outpostHex } from '../sim/village.js';
import type { HandlerRegistry } from './events.js';
import { armyHandlers, rallyTrained } from './armies.js';
import { groupHandlers, groupTrained, joinGroup } from './armyGroups.js';
import { seasonHandlers } from './seasons.js';
import { loadArmy } from '../db/armies.js';
import { batchCompletesAt } from '../sim/training.js';
import { battleHandlers } from './battles.js';
import { caravanHandlers } from './caravans.js';
import { expeditionHandlers } from './expeditions.js';
import { fieldHandlers } from './field.js';
import { terraformHandlers } from './terraform.js';
import { hordeHandlers } from './horde.js';
import { campHandlers } from './camps.js';
import { mapEventHandlers } from './mapEvents.js';
import { pruneHandlers } from './prune.js';
import { siteHandlers } from './sites.js';
import { raidHandlers } from './raids.js';
import { bridgeHandlers } from './bridge.js';
import { ritualHandlers } from './ritual.js';
import { heroHandlers } from './heroes.js';
import { generalHandlers } from './generals.js';
import { questHandlers } from './quests.js';
import { noticeHandlers } from './notices.js';
import { orderHandlers } from './orders.js';
import { refreshBonuses, researchHandlers, settleResearchPoints } from './research.js';
import { outpostHandlers, outpostStanding } from './outposts.js';
import { tell } from './notices.js';
import { scoutingHandlers } from './scouting.js';
import { smithingHandlers } from './smithing.js';
import { waveHandlers } from './waves.js';
import { fortHandlers } from './forts.js';
import { edgeWallHandlers } from './edgeWalls.js';

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
    // A raid or raze cleared the queue before it was finished, or it was
    // cancelled, or moved up (a later event of its own finishes it).
    if (!village.state.queue.some((item) => item.plot === plot && item.targetLevel === payload.targetLevel && item.completesAt.getTime() === event.dueAt.getTime())) return;
    // An Academy's level changes what research comes in from now on.
    if (data.buildings.buildings[payload.building]?.research && village.ownerAccountId !== null) {
      await settleResearchPoints(client, data, world, village.ownerAccountId, event.dueAt);
    }
    const state = completeBuild(data, village.state, plot, payload.targetLevel, event.dueAt, world.speed);
    await saveVillageState(client, village.id, state);
    // A Shrine's new level: its god's blessing grows in all the owner's villages.
    if (data.buildings.buildings[payload.building]?.deities && village.ownerAccountId !== null) {
      await refreshBonuses(client, data, world, [village.ownerAccountId], event.dueAt);
    }
    const def = data.buildings.buildings[payload.building];
    const big = payload.building === 'elder_hall' || payload.targetLevel >= data.notifications.bigBuildLevel;
    await tell(client, world, village.ownerAccountId, {
      kind: 'build_done',
      tier: big ? 'push' : 'digest',
      title: '{building} level {level} in {village}',
      body: big ? 'Finished. Your build queue may have room for more.' : 'Finished.',
      vars: { building: def?.name ?? payload.building, level: payload.targetLevel, village: village.name },
    }, event.dueAt);
    const cell = outpostHex(plot);
    if (cell && payload.targetLevel === 1) {
      await outpostStanding(client, data, world, { villageId: village.id, plot, cell }, event.dueAt);
    }
    await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
  },

  // A batch finished: move its units into the garrison.
  async training_complete({ client, data, world }, event) {
    const payload = trainingCompletePayload.parse(event.payload);
    const village = await loadVillage(client, payload.villageId);
    const done = village.state.training.filter((batch) => batchCompletesAt(batch) <= event.dueAt);
    await saveVillageState(client, village.id, completeTraining(village.state, event.dueAt));
    // Those trained for an army group march to it; the others on to the
    // owner's rally point, if one is set.
    await groupTrained(client, data, world, village.id, done, event.dueAt);
    await rallyTrained(client, data, world, village.id, done.filter((batch) => batch.group === undefined), event.dueAt);
    await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
  },

  ...waveHandlers,
  ...scoutingHandlers,
  ...battleHandlers,
  ...outpostHandlers,
  ...caravanHandlers,
  ...expeditionHandlers,
  ...researchHandlers,
  ...smithingHandlers,
  ...heroHandlers,
  ...generalHandlers,
  ...questHandlers,
  ...orderHandlers,
  ...noticeHandlers,
  ...armyHandlers,
  // An army marching to join an army group joins it once it stands.
  async army_arrive(context, event) {
    const { armyId } = z.object({ armyId: z.number().int() }).parse(event.payload);
    const before = await loadArmy(context.client, armyId);
    const due = before.status === 'marching' && before.arrivesAt.getTime() === event.dueAt.getTime();
    await armyHandlers.army_arrive!(context, event);
    if (due && before.groupId !== null) await joinGroup(context.client, context.data, context.world, await loadArmy(context.client, armyId), event.dueAt);
  },
  ...groupHandlers,
  ...seasonHandlers,
  ...fieldHandlers,
  ...terraformHandlers,
  ...fortHandlers,
  ...edgeWallHandlers,
  ...hordeHandlers,
  ...campHandlers,
  ...mapEventHandlers,
  ...pruneHandlers,
  ...siteHandlers,
  ...raidHandlers,
  ...bridgeHandlers,
  ...ritualHandlers,
};
