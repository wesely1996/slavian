import type { Stance, TerrainId } from '../data/index.js';
import { ForbiddenError, NotFoundError, RuleError } from '../errors.js';
import { insertMission, type ScoutMission } from '../db/scouting.js';
import { loadWave } from '../db/waves.js';
import { notifyWorld } from '../db/notify.js';
import type { Db, DbClient } from '../db/pool.js';
import { loadVillage, saveVillageState, type Village } from '../db/villages.js';
import { getWorld, loadHexes, type World } from '../db/worlds.js';
import { scheduleEvent, type SchedulerDeps } from '../scheduler/events.js';
import type { BuildCompletePayload, TrainingCompletePayload } from '../scheduler/handlers.js';
import type { MissionPayload } from '../scheduler/scouting.js';
import { hex } from '../sim/hex.js';
import { SCOUT_UNIT, scoutTarget, scoutTravelMs } from '../sim/scouting.js';
import { withWorld } from '../scheduler/world.js';
import { batchCompletesAt, type TrainingBatch } from '../sim/training.js';
import { queueBuild, queueTraining, sendAway, type QueuedBuild, type VillageState } from '../sim/village.js';

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

// Sends scouts from the caller's village to a wave. They report on arrival
// and walk back the same way.
export async function sendScoutsCommand(
  db: Db,
  deps: SchedulerDeps,
  input: VillageCommandInput & { waveId: number; count: number },
): Promise<{ village: Village; mission: ScoutMission }> {
  const { village, result } = await ownVillageCommand(db, deps, input, async ({ client, world, village }) => {
    const max = deps.data.scouting.maxScouts;
    if (!Number.isInteger(input.count) || input.count < 1 || input.count > max) {
      throw new RuleError(`Send between 1 and ${max} scouts`);
    }
    const wave = await loadWave(client, input.waveId);
    if (wave.worldId !== world.id) throw new NotFoundError(`Wave ${input.waveId} not found`);
    if (wave.status === 'dispersed' || wave.status === 'defeated') throw new RuleError('That horde has already scattered');

    const state = sendAway(village.state, SCOUT_UNIT, input.count, input.now);
    const terrain = new Map<string, TerrainId>((await loadHexes(client, world.id)).map(([q, r, t]) => [`${q},${r}`, t]));
    const home = hex(village.q, village.r);
    const target = scoutTarget(deps.data, terrain, wave, home, input.now);
    const travelMs = scoutTravelMs(deps.data, terrain, home, target, world.speed);
    const arrivesAt = new Date(input.now.getTime() + travelMs);
    const mission = await insertMission(client, {
      worldId: world.id,
      villageId: village.id,
      waveId: wave.id,
      sent: input.count,
      target,
      departsAt: input.now,
      arrivesAt,
      returnsAt: new Date(arrivesAt.getTime() + travelMs),
    });
    const payload: MissionPayload = { missionId: mission.id };
    await scheduleEvent(client, world.id, arrivesAt, 'scout_arrive', payload);
    await notifyWorld(client, { worldId: world.id, type: 'scouting' });
    return { state, result: mission };
  });
  return { village, mission: result };
}

// Sets how the village's garrison fights; takes effect from the next round.
export async function setStanceCommand(
  db: Db,
  deps: SchedulerDeps,
  input: VillageCommandInput & { stance: Stance },
): Promise<{ village: Village }> {
  const { village } = await ownVillageCommand(db, deps, input, async ({ village }) => ({
    state: { ...village.state, stance: input.stance },
    result: null,
  }));
  return { village };
}
