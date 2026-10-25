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
import { fieldsFromLand, landAround, loseAway, newVillage, outpostHex, outpostPlots, returnHome } from '../sim/village.js';
import { tell } from './notices.js';
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
    const land = new Map((await loadHexes(client, world.id)).map(([q, r, t]) => [hexKey(hex(q, r)), t as TerrainId] as const));
    const terrain = land.get(hexKey(cell));
    const problem = settleProblem(data, {
      cell,
      terrain,
      home: hex(home.q, home.r),
      villages: villages.map((v) => hex(v.q, v.r)),
      outposts,
    });
    if (problem) {
      await markTurnedBack(client, expedition.id, problem);
      await tell(client, world, home.ownerAccountId, {
        kind: 'settlers',
        tier: 'digest',
        title: 'Settlers turned back from ({q}, {r})',
        body: '{problem}. They are walking home to {home}.',
        vars: { q: expedition.q, r: expedition.r, problem, home: home.name },
      }, event.dueAt);
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
        fields: fieldsFromLand(data, landAround(data, land, cell)),
      }),
    });
    // The settlers become the new village's people: they stop eating at home.
    await saveVillageState(client, home.id, loseAway(data, home.state, SETTLER, expedition.settlers, event.dueAt, world.speed));
    await markFounded(client, expedition.id, founded.id);
    await tell(client, world, owner, {
      kind: 'settlers',
      tier: 'digest',
      title: '{name} founded',
      body: 'Your settlers built a new village.',
      vars: { name: expedition.name },
    }, event.dueAt);
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
