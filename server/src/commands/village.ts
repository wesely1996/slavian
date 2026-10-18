import { ForbiddenError, NotFoundError } from '../errors.js';
import { notifyWorld } from '../db/notify.js';
import type { Db, DbClient } from '../db/pool.js';
import { loadVillage, saveVillageState, type Village } from '../db/villages.js';
import { getWorld, type World } from '../db/worlds.js';
import { scheduleEvent, type SchedulerDeps } from '../scheduler/events.js';
import type { BuildCompletePayload, TrainingCompletePayload } from '../scheduler/handlers.js';
import { withWorld } from '../scheduler/world.js';
import { batchCompletesAt, type TrainingBatch } from '../sim/training.js';
import { queueBuild, queueTraining, type QueuedBuild, type VillageState } from '../sim/village.js';

interface VillageCommandInput {
  accountId: number;
  villageId: number;
  now: Date;
}

// Runs a command on the caller's own village with the world locked and
// caught up to `now`, then saves the village and announces the change.
async function ownVillageCommand<T>(
  db: Db,
  deps: SchedulerDeps,
  input: VillageCommandInput,
  apply: (ctx: { client: DbClient; world: World; village: Village }) => Promise<{ state: VillageState; result: T }>,
): Promise<{ village: Village; result: T }> {
  const { rows } = await db.query<{ world_id: number }>('SELECT world_id FROM villages WHERE id = $1', [
    input.villageId,
  ]);
  if (!rows[0]) throw new NotFoundError(`Village ${input.villageId} not found`);
  const worldId = rows[0].world_id;

  return withWorld(db, worldId, input.now, deps, async (client) => {
    const world = await getWorld(client, worldId);
    const village = await loadVillage(client, input.villageId);
    if (village.ownerAccountId !== input.accountId) throw new ForbiddenError('Not your village');
    const { state, result } = await apply({ client, world, village });
    await saveVillageState(client, village.id, state);
    await notifyWorld(client, { worldId, type: 'village', villageId: village.id });
    return { village: { ...village, state }, result };
  });
}

export async function queueBuildCommand(
  db: Db,
  deps: SchedulerDeps,
  input: VillageCommandInput & { building: string },
): Promise<{ village: Village; queued: QueuedBuild }> {
  const { village, result } = await ownVillageCommand(db, deps, input, async ({ client, world, village }) => {
    const { state, queued } = queueBuild(deps.data, village.state, input.building, input.now, world.speed);
    const payload: BuildCompletePayload = {
      villageId: village.id,
      building: queued.building,
      targetLevel: queued.targetLevel,
    };
    await scheduleEvent(client, world.id, queued.completesAt, 'build_complete', payload);
    return { state, result: queued };
  });
  return { village, queued: result };
}

export async function trainUnitsCommand(
  db: Db,
  deps: SchedulerDeps,
  input: VillageCommandInput & { unit: string; count: number },
): Promise<{ village: Village; batch: TrainingBatch }> {
  const { village, result } = await ownVillageCommand(db, deps, input, async ({ client, world, village }) => {
    const { state, batch } = queueTraining(deps.data, village.state, input.unit, input.count, input.now, world.speed);
    const payload: TrainingCompletePayload = { villageId: village.id };
    await scheduleEvent(client, world.id, batchCompletesAt(batch), 'training_complete', payload);
    return { state, result: batch };
  });
  return { village, batch: result };
}
