// Settlers on the scheduler: settlers_arrive founds the village (or turns
// the settlers back if the hex was taken meanwhile); settlers_return brings
// them home.
import { z } from 'zod';
import type { TerrainId } from '../data/index.js';
import { countVillagesOwned, loadExpedition, markExpeditionDone, markFounded, markTurnedBack } from '../db/expeditions.js';
import { notifyWorld } from '../db/notify.js';
import { insertVillage, listVillages, loadVillage, saveVillageState } from '../db/villages.js';
import { loadHexes } from '../db/worlds.js';
import { adminUpkeepFor, SETTLER, settleProblem } from '../sim/expansion.js';
import { hex, hexKey } from '../sim/hex.js';
import { loseAway, newVillage, outpostHex, outpostPlots, returnHome } from '../sim/village.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';

export const expeditionPayload = z.object({ expeditionId: z.number().int() });
export type ExpeditionPayload = z.infer<typeof expeditionPayload>;

export const expeditionHandlers: HandlerRegistry = {
  async settlers_arrive({ client, data, world }, event) {
    const expedition = await loadExpedition(client, expeditionPayload.parse(event.payload).expeditionId);
    if (expedition.status !== 'outbound') return;
    const home = await loadVillage(client, expedition.villageId);
    const villages = await listVillages(client, world.id);
    const outposts = new Set(villages.flatMap((v) => outpostPlots(v.state.plots).map((plot) => hexKey(outpostHex(plot)!))));
    const cell = hex(expedition.q, expedition.r);
    const terrain = (await loadHexes(client, world.id)).find(([q, r]) => q === cell.q && r === cell.r)?.[2] as TerrainId | undefined;
    const problem = settleProblem(data, {
      cell,
      terrain,
      home: hex(home.q, home.r),
      villages: villages.map((v) => hex(v.q, v.r)),
      outposts,
    });
    if (problem) {
      await markTurnedBack(client, expedition.id, problem);
      const payload: ExpeditionPayload = { expeditionId: expedition.id };
      await scheduleEvent(client, world.id, expedition.returnsAt, 'settlers_return', payload);
      await notifyWorld(client, { worldId: world.id, type: 'expeditions' });
      return;
    }

    const owner = home.ownerAccountId!;
    const owned = await countVillagesOwned(client, world.id, owner);
    const founded = await insertVillage(client, {
      worldId: world.id,
      ownerAccountId: owner,
      name: expedition.name,
      q: cell.q,
      r: cell.r,
      state: newVillage(data, event.dueAt, world.speed, {
        startingResources: data.expansion.startingResources,
        adminUpkeep: adminUpkeepFor(data, owned),
        bonuses: home.state.bonuses,
      }),
    });
    // The settlers become the new village's people: they stop eating at home.
    await saveVillageState(client, home.id, loseAway(data, home.state, SETTLER, expedition.settlers, event.dueAt, world.speed));
    await markFounded(client, expedition.id, founded.id);
    await notifyWorld(client, { worldId: world.id, type: 'world' });
  },

  async settlers_return({ client, world }, event) {
    const expedition = await loadExpedition(client, expeditionPayload.parse(event.payload).expeditionId);
    if (expedition.status !== 'returning') return;
    const home = await loadVillage(client, expedition.villageId);
    await saveVillageState(client, home.id, returnHome(home.state, SETTLER, expedition.settlers));
    await markExpeditionDone(client, expedition.id);
    await notifyWorld(client, { worldId: world.id, type: 'village', villageId: home.id });
    await notifyWorld(client, { worldId: world.id, type: 'expeditions' });
  },
};
