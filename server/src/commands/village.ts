import type { Stance, TerrainId } from '../data/index.js';
import { ForbiddenError, NotFoundError, RuleError } from '../errors.js';
import { effectiveBonuses } from '../db/heroes.js';
import { countVillagesOwned, insertExpedition, outboundTo, type Expedition } from '../db/expeditions.js';
import { listResearch, startResearch, type ResearchEntry } from '../db/research.js';
import { insertMission, type ScoutMission } from '../db/scouting.js';
import { loadWave } from '../db/waves.js';
import { notifyWorld } from '../db/notify.js';
import type { Db, DbClient } from '../db/pool.js';
import { listVillages, loadVillage, saveVillageState, type Village } from '../db/villages.js';
import { getWorld, loadHexes, type World } from '../db/worlds.js';
import { scheduleEvent, type SchedulerDeps } from '../scheduler/events.js';
import type { BuildCompletePayload, TrainingCompletePayload } from '../scheduler/handlers.js';
import type { ExpeditionPayload } from '../scheduler/expeditions.js';
import type { ResearchPayload } from '../scheduler/research.js';
import type { MissionPayload } from '../scheduler/scouting.js';
import { hex, hexKey, type Hex } from '../sim/hex.js';
import { SETTLER, settleProblem } from '../sim/expansion.js';
import { roadRoute } from '../sim/logistics.js';
import { ACADEMY, researchMs, researchProblem } from '../sim/research.js';
import { spend } from '../sim/resources.js';
import { SCOUT_UNIT, scoutTarget, scoutTravelMs } from '../sim/scouting.js';
import { withWorld } from '../scheduler/world.js';
import { startRebuild } from '../scheduler/horde.js';
import { rebuildCost } from '../sim/horde.js';
import { batchCompletesAt, type TrainingBatch } from '../sim/training.js';
import {
  abandonOutpost,
  claimOutpost,
  NotEnoughUnitsError,
  outpostHex,
  outpostPlot,
  outpostPlots,
  queueBuild,
  queueTraining,
  sendAway,
  type BuildOrder,
  type QueuedBuild,
  type VillageState,
} from '../sim/village.js';

export interface VillageCommandInput {
  accountId: number;
  villageId: number;
  now: Date;
  // Commands that work on a razed village (rebuilding it).
  allowRuin?: boolean;
}

// Runs a command on the caller's own village with the world locked and
// caught up to `now`, then saves the village and announces the change.
export async function ownVillageCommand<T>(
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
    if (village.ruin && !input.allowRuin) throw new RuleError(`${village.name} lies in ruins; rebuild it first`);
    const { state, result } = await apply({ client, world, village });
    await saveVillageState(client, village.id, state);
    await notifyWorld(client, { worldId, type: 'village', villageId: village.id });
    return { village: { ...village, state }, result };
  });
}

export async function queueBuildCommand(
  db: Db,
  deps: SchedulerDeps,
  input: VillageCommandInput & BuildOrder,
): Promise<{ village: Village; queued: QueuedBuild }> {
  const { village, result } = await ownVillageCommand(db, deps, input, async ({ client, world, village }) => {
    const order: BuildOrder = {
      ...(input.plot ? { plot: input.plot } : {}),
      ...(input.building ? { building: input.building } : {}),
    };
    const { state, queued } = queueBuild(deps.data, village.state, order, input.now, world.speed);
    const payload: BuildCompletePayload = {
      villageId: village.id,
      plot: queued.plot,
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
    const owned = await countVillagesOwned(client, world.id, village.ownerAccountId!);
    const { state, batch } = queueTraining(deps.data, village.state, input.unit, input.count, input.now, world.speed, owned);
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
    const travelMs = scoutTravelMs(deps.data, terrain, home, target, world.speed, await effectiveBonuses(client, deps.data, village));
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

// Claims a resource hex near the caller's village and starts building an
// outpost there. Upgrades go through the build queue like any plot.
export async function claimOutpostCommand(
  db: Db,
  deps: SchedulerDeps,
  input: VillageCommandInput & { q: number; r: number },
): Promise<{ village: Village; queued: QueuedBuild }> {
  const { village, result } = await ownVillageCommand(db, deps, input, async ({ client, world, village }) => {
    const cell = hex(input.q, input.r);
    const terrain = (await loadHexes(client, world.id)).find(([q, r]) => q === cell.q && r === cell.r)?.[2];
    if (!terrain) throw new RuleError('That hex is not on the map');
    const taken = new Set<string>();
    for (const other of await listVillages(client, world.id)) {
      taken.add(hexKey(hex(other.q, other.r)));
      for (const plot of outpostPlots(other.state.plots)) taken.add(hexKey(outpostHex(plot)!));
    }
    const site = { cell, terrain, home: hex(village.q, village.r), taken };
    const { state, queued } = claimOutpost(deps.data, village.state, site, input.now, world.speed);
    const payload: BuildCompletePayload = {
      villageId: village.id,
      plot: queued.plot,
      building: queued.building,
      targetLevel: queued.targetLevel,
    };
    await scheduleEvent(client, world.id, queued.completesAt, 'build_complete', payload);
    return { state, result: queued };
  });
  return { village, queued: result };
}

export async function abandonOutpostCommand(
  db: Db,
  deps: SchedulerDeps,
  input: VillageCommandInput & { q: number; r: number },
): Promise<{ village: Village }> {
  const cell: Hex = hex(input.q, input.r);
  const { village } = await ownVillageCommand(db, deps, input, async ({ world, village }) => ({
    state: abandonOutpost(deps.data, village.state, outpostPlot(cell), input.now, world.speed),
    result: null,
  }));
  return { village };
}

// Sends settlers from the caller's village to found a new one on a free
// hex. The site is checked again when they arrive.
export async function foundVillageCommand(
  db: Db,
  deps: SchedulerDeps,
  input: VillageCommandInput & { q: number; r: number; name?: string },
): Promise<{ village: Village; expedition: Expedition }> {
  const { village, result } = await ownVillageCommand(db, deps, input, async ({ client, world, village }) => {
    const cell = hex(input.q, input.r);
    const hexes = await loadHexes(client, world.id);
    const terrain = new Map<string, TerrainId>(hexes.map(([q, r, t]) => [`${q},${r}`, t]));
    const villages = await listVillages(client, world.id);
    const outposts = new Set(villages.flatMap((v) => outpostPlots(v.state.plots).map((plot) => hexKey(outpostHex(plot)!))));
    const home = hex(village.q, village.r);
    const problem = settleProblem(deps.data, {
      cell,
      terrain: terrain.get(hexKey(cell)),
      home,
      villages: villages.map((v) => hex(v.q, v.r)),
      outposts,
    });
    if (problem) throw new RuleError(problem);
    if (await outboundTo(client, world.id, cell.q, cell.r)) throw new RuleError('Settlers are already on their way there');

    const settlers = deps.data.expansion.settlersNeeded;
    let state: VillageState;
    try {
      state = sendAway(village.state, SETTLER, settlers, input.now);
    } catch (error) {
      if (error instanceof NotEnoughUnitsError) throw new RuleError(`Founding a village takes ${settlers} settlers at home`);
      throw error;
    }
    const path = roadRoute(deps.data, terrain, home, cell, deps.data.units.units[SETTLER]!.speed, world.speed);
    const travelMs = path.at(-1)!.atMs;
    const arrivesAt = new Date(input.now.getTime() + travelMs);
    const owned = await countVillagesOwned(client, world.id, village.ownerAccountId!);
    const { rows } = await client.query<{ display_name: string }>('SELECT display_name FROM accounts WHERE id = $1', [
      village.ownerAccountId,
    ]);
    const expedition = await insertExpedition(client, {
      worldId: world.id,
      villageId: village.id,
      q: cell.q,
      r: cell.r,
      name: input.name?.trim() || `${rows[0]?.display_name ?? 'New'}'s village ${owned + 1}`,
      settlers,
      path,
      departsAt: input.now,
      arrivesAt,
      returnsAt: new Date(arrivesAt.getTime() + travelMs),
    });
    const payload: ExpeditionPayload = { expeditionId: expedition.id };
    await scheduleEvent(client, world.id, arrivesAt, 'settlers_arrive', payload);
    await notifyWorld(client, { worldId: world.id, type: 'expeditions' });
    return { state, result: expedition };
  });
  return { village, expedition: result };
}

// Starts researching `tech` in the caller's village Academy, paid by the
// village. Research belongs to the player: its effects reach all their
// villages when it completes.
export async function startResearchCommand(
  db: Db,
  deps: SchedulerDeps,
  input: VillageCommandInput & { tech: string },
): Promise<{ village: Village; research: ResearchEntry }> {
  const { village, result } = await ownVillageCommand(db, deps, input, async ({ client, world, village }) => {
    const accountId = village.ownerAccountId!;
    const entries = await listResearch(client, world.id, accountId);
    const problem = researchProblem(deps.data, input.tech, {
      academyLevel: village.state.levels[ACADEMY] ?? 0,
      done: new Set(entries.filter((e) => e.status === 'done').map((e) => e.tech)),
      researching: entries.some((e) => e.status === 'researching'),
    });
    if (problem) throw new RuleError(problem);
    const ledger = spend(village.state.ledger, input.now, deps.data.research.techs[input.tech]!.cost);
    const completesAt = new Date(input.now.getTime() + researchMs(deps.data, input.tech, world.speed));
    const research = await startResearch(client, {
      worldId: world.id,
      accountId,
      tech: input.tech,
      villageId: village.id,
      startedAt: input.now,
      completesAt,
    });
    const payload: ResearchPayload = { accountId, tech: input.tech };
    await scheduleEvent(client, world.id, completesAt, 'research_complete', payload);
    await notifyWorld(client, { worldId: world.id, type: 'research' });
    return { state: { ...village.state, ledger }, result: research };
  });
  return { village, research: result };
}

// Rebuilds a razed village: pays a share of what stood, and it stands again
// after the rebuild time.
export async function rebuildCommand(db: Db, deps: SchedulerDeps, input: VillageCommandInput): Promise<{ village: Village; result: Date }> {
  const done = await ownVillageCommand(db, deps, { ...input, allowRuin: true }, async ({ client, world, village }) => {
    if (!village.ruin) throw new RuleError(`${village.name} is not in ruins`);
    if (village.ruin.rebuildingUntil) throw new RuleError(`${village.name} is already being rebuilt`);
    const state = { ...village.state, ledger: spend(village.state.ledger, input.now, rebuildCost(deps.data, village.ruin.plots)) };
    const until = await startRebuild(client, deps.data, world, village, input.now);
    await notifyWorld(client, { worldId: world.id, type: 'world' });
    return { state, result: until };
  });
  const { village } = done;
  return { ...done, village: { ...village, ruin: { ...village.ruin!, rebuildingUntil: done.result.toISOString() } } };
}
