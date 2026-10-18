import { ForbiddenError, NotFoundError } from '../errors.js';
import { notifyWorld } from '../db/notify.js';
import type { Db } from '../db/pool.js';
import { loadVillage, saveVillageState, type Village } from '../db/villages.js';
import { getWorld } from '../db/worlds.js';
import { scheduleEvent, type SchedulerDeps } from '../scheduler/events.js';
import type { BuildCompletePayload } from '../scheduler/handlers.js';
import { withWorld } from '../scheduler/world.js';
import { queueBuild, type QueuedBuild } from '../sim/village.js';

export async function queueBuildCommand(
  db: Db,
  deps: SchedulerDeps,
  input: { accountId: number; villageId: number; building: string; now: Date },
): Promise<{ village: Village; queued: QueuedBuild }> {
  const { rows } = await db.query<{ world_id: number }>('SELECT world_id FROM villages WHERE id = $1', [
    input.villageId,
  ]);
  if (!rows[0]) throw new NotFoundError(`Village ${input.villageId} not found`);
  const worldId = rows[0].world_id;

  return withWorld(db, worldId, input.now, deps, async (client) => {
    const world = await getWorld(client, worldId);
    const village = await loadVillage(client, input.villageId);
    if (village.ownerAccountId !== input.accountId) throw new ForbiddenError('Not your village');

    const { state, queued } = queueBuild(deps.data, village.state, input.building, input.now, world.speed);
    await saveVillageState(client, village.id, state);
    const payload: BuildCompletePayload = {
      villageId: village.id,
      building: queued.building,
      targetLevel: queued.targetLevel,
    };
    await scheduleEvent(client, worldId, queued.completesAt, 'build_complete', payload);
    await notifyWorld(client, { worldId, type: 'village', villageId: village.id });
    return { village: { ...village, state }, queued };
  });
}
