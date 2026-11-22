// Forts as strongholds on the scheduler (forts.json): a building rising a
// level, paid from the village that built the fort, and tearing a fort or
// supply point down.
import { z } from 'zod';
import type { GameData } from '../data/index.js';
import { RuleError } from '../errors.js';
import { deleteFort, loadFort, saveFortBuildings, type Fort } from '../db/forts.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { loadVillage, saveVillageState } from '../db/villages.js';
import type { World } from '../db/worlds.js';
import { fortBuildingDef, fortBuildMs, fortBuildProblem, fortLevelCost, levelOf } from '../sim/forts.js';
import { spend } from '../sim/resources.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';
import { tell } from './notices.js';

export const fortWorkPayload = z.object({ fortId: z.number().int(), plot: z.string(), level: z.number().int() });

// Starts `kind` rising a level on the fort's `plot`.
export async function buildInFort(client: DbClient, data: GameData, world: World, fort: Fort, plot: string, kind: string, at: Date): Promise<Fort> {
  if (fort.kind !== 'fort') throw new RuleError('Only a fort has buildings');
  if (fort.status !== 'standing') throw new RuleError('The fort is not finished yet');
  if (fort.villageId === null) throw new RuleError('The village that built this fort is gone');
  const problem = fortBuildProblem(data, fort.plots, fort.work, plot, kind);
  if (problem) throw new RuleError(problem);
  const def = fortBuildingDef(data, plot, kind)!;
  const level = levelOf(fort.plots, plot) + 1;
  const village = await loadVillage(client, fort.villageId);
  if (village.ruin) throw new RuleError('The village that built this fort lies in ruins');
  await saveVillageState(client, village.id, { ...village.state, ledger: spend(village.state.ledger, at, fortLevelCost(def, level)) });
  const completesAt = new Date(at.getTime() + fortBuildMs(def, level, world.speed));
  const work = { plot, kind, level, completesAt: completesAt.toISOString() };
  await saveFortBuildings(client, fort.id, fort.plots, work);
  await scheduleEvent(client, world.id, completesAt, 'fort_work_done', { fortId: fort.id, plot, level });
  await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
  await notifyWorld(client, { worldId: world.id, type: 'armies' });
  return { ...fort, work };
}

// Tears a fort or supply point down: whatever it stored is lost.
export async function tearDownFort(client: DbClient, world: World, fort: Fort): Promise<void> {
  if (fort.neutral) throw new RuleError('That is nobody\'s to tear down');
  await deleteFort(client, fort.id);
  await notifyWorld(client, { worldId: world.id, type: 'armies' });
}

export const fortHandlers: HandlerRegistry = {
  async fort_work_done({ client, data, world }, event) {
    const payload = fortWorkPayload.parse(event.payload);
    const fort = await loadFort(client, payload.fortId);
    if (!fort?.work || fort.work.plot !== payload.plot || fort.work.level !== payload.level) return;
    const plots = { ...fort.plots, [fort.work.plot]: { kind: fort.work.kind, level: fort.work.level } };
    await saveFortBuildings(client, fort.id, plots, null);
    const def = fortBuildingDef(data, fort.work.plot, fort.work.kind);
    await tell(client, world, fort.ownerAccountId, {
      kind: 'build_done',
      tier: 'digest',
      title: '{building} level {level} in the fort at ({q}, {r})',
      body: 'The fort can build again.',
      vars: { building: def?.name ?? fort.work.kind, level: fort.work.level, q: fort.q, r: fort.r },
    }, event.dueAt);
    await notifyWorld(client, { worldId: world.id, type: 'armies' });
  },
};
