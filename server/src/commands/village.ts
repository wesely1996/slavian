import type { Stance, TerrainId } from '../data/index.js';
import { loadLand } from '../db/rivers.js';
import type { OnboardingStep } from '../data/index.js';
import { onboardingStep } from '../scheduler/onboarding.js';
import { authorize } from '../db/delegations.js';
import { ForbiddenError, NotFoundError, RuleError } from '../errors.js';
import { effectiveBonuses, listHeroes, loadHero, saveHero } from '../db/heroes.js';
import { listGenerals, saveGeneral } from '../db/generals.js';
import { countVillagesOwned, insertExpedition, outboundTo, type Expedition } from '../db/expeditions.js';
import { listResearch, loadResearchPoints, saveResearchPoints, startResearch, type ResearchEntry } from '../db/research.js';
import { insertMission, type ScoutMission } from '../db/scouting.js';
import { loadWave } from '../db/waves.js';
import { notifyWorld } from '../db/notify.js';
import type { Db, DbClient } from '../db/pool.js';
import { listVillages, loadVillage, saveVillageState, type Village } from '../db/villages.js';
import { getWorld, loadHexes, type World } from '../db/worlds.js';
import { scheduleEvent, type SchedulerDeps } from '../scheduler/events.js';
import type { BuildCompletePayload, TrainingCompletePayload } from '../scheduler/handlers.js';
import type { ExpeditionPayload } from '../scheduler/expeditions.js';
import { settleResearchPoints, type ResearchPayload } from '../scheduler/research.js';
import type { MissionPayload } from '../scheduler/scouting.js';
import { hex, hexDistance, hexKey, type Hex } from '../sim/hex.js';
import { SETTLER, settleProblem } from '../sim/expansion.js';
import { roadRoute, store, vaultCapacity } from '../sim/logistics.js';
import { ACADEMY, researchCost, researchMs, researchProblem } from '../sim/research.js';
import { spend, type ResourceKind, type Resources } from '../sim/resources.js';
import { loadVault, saveVault } from '../db/vaults.js';
import { SCOUT_UNIT, scoutTarget, scoutTravelMs } from '../sim/scouting.js';
import { withWorld } from '../scheduler/world.js';
import { startRebuild } from '../scheduler/horde.js';
import { campAt } from '../db/camps.js';
import { listScrolls, siteAt } from '../db/sites.js';
import { rebuildCost } from '../sim/horde.js';
import { batchCompletesAt, type TrainingBatch } from '../sim/training.js';
import { townName } from '../sim/names.js';
import { createRng } from '../sim/rng.js';
import {
  abandonOutpost,
  claimOutpost,
  completeTraining,
  demolish,
  joinGarrison,
  NotEnoughUnitsError,
  refundOf,
  researchPerHour,
  sellGear,
  trade,
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
  // What the command does, for the delegation log ("queued a build").
  action?: string;
}

// Runs a command on the caller's own village with the world locked and
// caught up to `now`, then saves the village and announces the change.
export async function ownVillageCommand<T>(
  db: Db,
  deps: SchedulerDeps,
  input: VillageCommandInput,
  apply: (ctx: { client: DbClient; world: World; village: Village }) => Promise<{ state: VillageState; result: T; onboarding?: OnboardingStep | null }>,
): Promise<{ village: Village; result: T }> {
  const { rows } = await db.query<{ world_id: number }>('SELECT world_id FROM villages WHERE id = $1', [
    input.villageId,
  ]);
  if (!rows[0]) throw new NotFoundError(`Village ${input.villageId} not found`);
  const worldId = rows[0].world_id;

  return withWorld(db, worldId, input.now, deps, async (client) => {
    const world = await getWorld(client, worldId);
    const village = await loadVillage(client, input.villageId);
    await authorize(client, {
      worldId,
      ownerAccountId: village.ownerAccountId,
      actorAccountId: input.accountId,
      at: input.now,
      action: input.action ?? 'gave orders',
      villageId: village.id,
    });
    if (village.ruin && !input.allowRuin) throw new RuleError(`${village.name} lies in ruins; rebuild it first`);
    const { state, result, onboarding } = await apply({ client, world, village });
    await saveVillageState(client, village.id, state);
    await notifyWorld(client, { worldId, type: 'village', villageId: village.id });
    if (!onboarding) return { village: { ...village, state }, result };
    // A getting-started step's reward may land in this very village.
    await onboardingStep(client, deps.data, world, village.ownerAccountId, onboarding, input.now);
    return { village: await loadVillage(client, village.id), result };
  });
}

export async function queueBuildCommand(
  db: Db,
  deps: SchedulerDeps,
  input: VillageCommandInput & BuildOrder,
): Promise<{ village: Village; queued: QueuedBuild }> {
  const { village, result } = await ownVillageCommand(db, deps, { ...input, action: 'queued a build' }, async ({ client, world, village }) => {
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
    return { state, result: queued, onboarding: 'build' };
  });
  return { village, queued: result };
}

export async function trainUnitsCommand(
  db: Db,
  deps: SchedulerDeps,
  input: VillageCommandInput & { unit: string; count: number },
): Promise<{ village: Village; batch: TrainingBatch }> {
  const { village, result } = await ownVillageCommand(db, deps, { ...input, action: 'queued training' }, async ({ client, world, village }) => {
    const owned = await countVillagesOwned(client, world.id, village.ownerAccountId!);
    const { state, batch } = queueTraining(deps.data, village.state, input.unit, input.count, input.now, world.speed, owned);
    const payload: TrainingCompletePayload = { villageId: village.id };
    await scheduleEvent(client, world.id, batchCompletesAt(batch), 'training_complete', payload);
    return { state, result: batch, onboarding: 'train' };
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
  const { village, result } = await ownVillageCommand(db, deps, { ...input, action: 'sent scouts' }, async ({ client, world, village }) => {
    const max = deps.data.scouting.maxScouts;
    if (!Number.isInteger(input.count) || input.count < 1 || input.count > max) {
      throw new RuleError(`Send between 1 and ${max} scouts`);
    }
    const wave = await loadWave(client, input.waveId);
    if (wave.worldId !== world.id) throw new NotFoundError(`Wave ${input.waveId} not found`);
    if (wave.status === 'dispersed' || wave.status === 'defeated') throw new RuleError('That horde has already scattered');

    const state = sendAway(village.state, SCOUT_UNIT, input.count, input.now);
    const terrain = await loadLand(client, world.id);
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
    return { state, result: mission, onboarding: 'scout' };
  });
  return { village, mission: result };
}

// Sets how the village's garrison fights; takes effect from the next round.
export async function setStanceCommand(
  db: Db,
  deps: SchedulerDeps,
  input: VillageCommandInput & { stance: Stance },
): Promise<{ village: Village }> {
  const { village } = await ownVillageCommand(db, deps, { ...input, action: 'changed the stance' }, async ({ village }) => ({
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
  const { village, result } = await ownVillageCommand(db, deps, { ...input, action: 'claimed an outpost' }, async ({ client, world, village }) => {
    const cell = hex(input.q, input.r);
    const terrain = (await loadHexes(client, world.id)).find(([q, r]) => q === cell.q && r === cell.r)?.[2];
    if (!terrain) throw new RuleError('That hex is not on the map');
    if (await campAt(client, world.id, cell.q, cell.r)) throw new RuleError('A camp stands there; clear it first');
    if ((await siteAt(client, world.id, cell.q, cell.r))?.status === 'unexplored') throw new RuleError('An ancient site lies there');
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
    return { state, result: queued, onboarding: 'outpost' };
  });
  return { village, queued: result };
}

export async function abandonOutpostCommand(
  db: Db,
  deps: SchedulerDeps,
  input: VillageCommandInput & { q: number; r: number },
): Promise<{ village: Village }> {
  const cell: Hex = hex(input.q, input.r);
  const { village } = await ownVillageCommand(db, deps, { ...input, action: 'abandoned an outpost' }, async ({ world, village }) => ({
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
  const { village, result } = await ownVillageCommand(db, deps, { ...input, action: 'sent settlers' }, async ({ client, world, village }) => {
    const cell = hex(input.q, input.r);
    const terrain = await loadLand(client, world.id);
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
    if (await campAt(client, world.id, cell.q, cell.r)) throw new RuleError('A camp stands there; clear it first');
    if ((await siteAt(client, world.id, cell.q, cell.r))?.status === 'unexplored') throw new RuleError('An ancient site lies there');
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
    // A name of its own unless the player gave one: none the world's towns
    // or settlers on the road already carry.
    const { rows: going } = await client.query<{ name: string }>("SELECT name FROM expeditions WHERE world_id = $1 AND status = 'outbound'", [world.id]);
    const taken = [...villages.map((v) => v.name), ...going.map((e) => e.name)];
    const name = input.name?.trim() || townName(deps.data, taken, createRng((world.seed ^ Math.imul(taken.length + 1, 0x9e3779b1)) >>> 0));
    const expedition = await insertExpedition(client, {
      worldId: world.id,
      villageId: village.id,
      q: cell.q,
      r: cell.r,
      name,
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
  const { village, result } = await ownVillageCommand(db, deps, { ...input, action: 'started research' }, async ({ client, world, village }) => {
    const accountId = village.ownerAccountId!;
    const entries = await listResearch(client, world.id, accountId);
    const problem = researchProblem(deps.data, input.tech, {
      academyLevel: village.state.levels[ACADEMY] ?? 0,
      done: new Set(entries.filter((e) => e.status === 'done').map((e) => e.tech)),
      researching: entries.some((e) => e.status === 'researching'),
      scrolls: new Set((await listScrolls(client, world.id)).map((s) => s.scroll)),
    });
    if (problem) throw new RuleError(problem);
    // Research comes from all the player's Academies, resources from this village.
    const needed = researchCost(deps.data, input.tech);
    const points = await settleResearchPoints(client, deps.data, world, accountId, input.now);
    if (points < needed) {
      throw new RuleError(`${deps.data.research.techs[input.tech]!.name} takes ${needed} research; your Academies have brought in ${Math.floor(points)}`);
    }
    const ledger = spend(village.state.ledger, input.now, deps.data.research.techs[input.tech]!.cost);
    await saveResearchPoints(client, world.id, accountId, { amount: points - needed, settledAt: input.now });
    const completesAt = new Date(input.now.getTime() + researchMs(deps.data, input.tech, world.speed, village.state.bonuses));
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
  const done = await ownVillageCommand(db, deps, { ...input, allowRuin: true, action: 'began rebuilding' }, async ({ client, world, village }) => {
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

// Tears down the building on a slot, giving back a share of what it cost.
export async function demolishCommand(
  db: Db,
  deps: SchedulerDeps,
  input: VillageCommandInput & { plot: string },
): Promise<{ village: Village; refund: Resources }> {
  const { village, result } = await ownVillageCommand(db, deps, { ...input, action: 'tore down a building' }, async ({ client, world, village }) => {
    const building = village.state.plots[input.plot]?.building;
    if (building && deps.data.buildings.buildings[building]?.research && village.ownerAccountId !== null) {
      await settleResearchPoints(client, deps.data, world, village.ownerAccountId, input.now);
    }
    const { state, refund } = demolish(deps.data, village.state, input.plot, input.now, world.speed);
    return { state, result: refund };
  });
  return { village, refund: result };
}

// Trades one resource for another at the village's Market.
export async function tradeCommand(
  db: Db,
  deps: SchedulerDeps,
  input: VillageCommandInput & { give: ResourceKind; get: ResourceKind; amount: number },
): Promise<{ village: Village; got: number }> {
  const { village, result } = await ownVillageCommand(db, deps, { ...input, action: 'traded at the market' }, async ({ village }) => {
    const { state, got } = trade(deps.data, village.state, input, input.now);
    return { state, result: got };
  });
  return { village, got: result };
}

// Sells a piece of the hero's spare gear (not worn) at the village's Market.
export async function sellGearCommand(db: Db, deps: SchedulerDeps, input: VillageCommandInput & { item: string }): Promise<{ village: Village }> {
  const { village } = await ownVillageCommand(db, deps, { ...input, action: 'sold gear at the market' }, async ({ client, world, village }) => {
    const hero = await loadHero(client, world.id, village.ownerAccountId!);
    const index = hero.inventory.indexOf(input.item);
    if (index < 0) throw new RuleError('The hero carries no such spare item');
    const state = sellGear(deps.data, village.state, input.now);
    await saveHero(client, { ...hero, inventory: hero.inventory.filter((_, i) => i !== index) });
    await notifyWorld(client, { worldId: world.id, type: 'heroes' });
    return { state, result: null };
  });
  return { village };
}

// Gives up a whole village: a share of everything that stood there goes to
// the Holy City vault, its garrison and the hero standing there move to the
// owner's nearest other village, and the hex is free again. Only a quiet
// village: nothing on the road from or to it, nothing still being built.
export async function abandonVillageCommand(db: Db, deps: SchedulerDeps, input: VillageCommandInput): Promise<{ worldId: number }> {
  const { rows } = await db.query<{ world_id: number }>('SELECT world_id FROM villages WHERE id = $1', [input.villageId]);
  if (!rows[0]) throw new NotFoundError(`Village ${input.villageId} not found`);
  const worldId = rows[0].world_id;
  await withWorld(db, worldId, input.now, deps, async (client) => {
    const world = await getWorld(client, worldId);
    const village = await loadVillage(client, input.villageId);
    if (village.ownerAccountId !== input.accountId) throw new ForbiddenError('Only its owner can abandon a town');
    if (village.refuge) throw new RuleError('A refugee camp is not yours to abandon');
    const home = hex(village.q, village.r);
    const others = (await listVillages(client, world.id)).filter((v) => v.ownerAccountId === village.ownerAccountId && v.id !== village.id && !v.ruin);
    const to = others.reduce<Village | null>((best, v) => (!best || hexDistance(hex(v.q, v.r), home) < hexDistance(hex(best.q, best.r), home) ? v : best), null);
    if (!to) throw new RuleError('Its people need another standing village of yours to move to');
    const busy = async (sql: string) => Number((await client.query<{ n: string }>(sql, [village.id])).rows[0]!.n) > 0;
    if (village.state.besieged || (await busy("SELECT count(*) AS n FROM battles WHERE village_id = $1 AND status = 'ongoing'"))) {
      throw new RuleError('Not while a battle is fought there');
    }
    if (await busy("SELECT count(*) AS n FROM waves WHERE target_village_id = $1 AND status IN ('marching', 'arrived', 'battling', 'razing')")) {
      throw new RuleError('A horde is on its way there');
    }
    const state = completeTraining(village.state, input.now);
    if (state.queue.length || state.training.length) throw new RuleError('Wait for its builds and training to finish');
    if (Object.values(state.away).some((n) => n > 0)) throw new RuleError('Wait for everyone away to come home');
    if (await busy("SELECT count(*) AS n FROM caravans WHERE (village_id = $1 OR destination_village_id = $1) AND status <> 'done'")) {
      throw new RuleError('Not while caravans are on the road to or from it');
    }
    if (await busy("SELECT count(*) AS n FROM armies WHERE (home_village_id = $1 OR target_village_id = $1) AND status <> 'done'")) {
      throw new RuleError('Not while armies march from it, to it or stand guard there');
    }
    // (Its standing orders' checks go with it.)
    if (await busy("SELECT count(*) AS n FROM scheduled_events WHERE status = 'pending' AND type <> 'orders_check' AND payload->>'villageId' = $1::text")) {
      throw new RuleError('It still has work under way');
    }
    const hero = (await listHeroes(client, world.id)).find((h) => h.villageId === village.id);
    if (hero?.status === 'traveling') throw new RuleError(`${hero.name} is on the way there`);
    const generals = (await listGenerals(client, world.id)).filter((g) => g.villageId === village.id);
    const coming = generals.find((g) => g.status === 'traveling');
    if (coming) throw new RuleError(`${coming.name} is on the way there`);

    if (researchPerHour(deps.data, village.state.plots, world.speed) > 0) {
      await settleResearchPoints(client, deps.data, world, input.accountId, input.now);
    }
    const vault = await loadVault(client, world.id);
    const refund = refundOf(deps.data, village.state.plots, deps.data.buildings.village.abandonRefund);
    await saveVault(client, { ...vault, amounts: store(vault.amounts, vaultCapacity(deps.data, vault.level), refund).amounts });
    await saveVillageState(client, to.id, joinGarrison(deps.data, completeTraining(to.state, input.now), state.garrison, input.now, world.speed));
    if (hero) await saveHero(client, { ...hero, villageId: to.id });
    for (const general of generals) await saveGeneral(client, { ...general, villageId: to.id });
    await client.query("DELETE FROM scheduled_events WHERE status = 'pending' AND type = 'orders_check' AND payload->>'villageId' = $1::text", [village.id]);
    await client.query('DELETE FROM villages WHERE id = $1', [village.id]);
    await notifyWorld(client, { worldId: world.id, type: 'village', villageId: to.id });
    await notifyWorld(client, { worldId: world.id, type: 'heroes' });
    await notifyWorld(client, { worldId: world.id, type: 'generals' });
    await notifyWorld(client, { worldId: world.id, type: 'world' });
  });
  return { worldId };
}

// Renames one of the caller's towns. Only its owner names it, not a stand-in.
export async function renameVillageCommand(db: Db, deps: SchedulerDeps, input: VillageCommandInput & { name: string }): Promise<{ village: Village }> {
  const { village } = await ownVillageCommand(db, deps, { ...input, action: 'renamed a town', allowRuin: true }, async ({ client, village }) => {
    if (village.ownerAccountId !== input.accountId) throw new ForbiddenError('Only its owner can rename a town');
    await client.query('UPDATE villages SET name = $2 WHERE id = $1', [village.id, input.name]);
    return { state: village.state, result: null };
  });
  return { village: { ...village, name: input.name } };
}
