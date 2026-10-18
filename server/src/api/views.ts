// JSON shapes sent to clients. Timestamps are ISO strings; clients compute
// current resources from the ledger and their offset to `serverTime`.
import type { DbClient } from '../db/pool.js';
import type { Village } from '../db/villages.js';
import { batchCompletesAt } from '../sim/training.js';
import { listVillages } from '../db/villages.js';
import { listMissions, type ScoutMission } from '../db/scouting.js';
import { listActiveWaves, type Wave } from '../db/waves.js';
import { listMembers, loadHexes, type World } from '../db/worlds.js';

export interface VillageView {
  id: number;
  worldId: number;
  ownerAccountId: number | null;
  name: string;
  q: number;
  r: number;
  levels: Record<string, number>;
  queue: { building: string; targetLevel: number; startsAt: string; completesAt: string }[];
  // Units at home as of the last settle; units finished since are counted
  // from `training` (each batch trains one unit every perUnitMs).
  garrison: Record<string, number>;
  away: Record<string, number>;
  training: { unit: string; count: number; startsAt: string; perUnitMs: number; completesAt: string }[];
  resources: {
    amounts: Record<string, number>;
    ratesPerHour: Record<string, number>;
    capacity: Record<string, number>;
    settledAt: string;
  };
}

export function villageView(village: Village): VillageView {
  const { levels, queue, ledger, garrison, training } = village.state;
  return {
    id: village.id,
    worldId: village.worldId,
    ownerAccountId: village.ownerAccountId,
    name: village.name,
    q: village.q,
    r: village.r,
    levels: { ...levels },
    queue: queue.map((item) => ({
      building: item.building,
      targetLevel: item.targetLevel,
      startsAt: item.startsAt.toISOString(),
      completesAt: item.completesAt.toISOString(),
    })),
    garrison: { ...garrison },
    away: { ...village.state.away },
    training: training.map((batch) => ({
      unit: batch.unit,
      count: batch.count,
      startsAt: batch.startsAt.toISOString(),
      perUnitMs: batch.perUnitMs,
      completesAt: batchCompletesAt(batch).toISOString(),
    })),
    resources: {
      amounts: ledger.amounts,
      ratesPerHour: ledger.ratesPerHour,
      capacity: ledger.capacity,
      settledAt: ledger.settledAt.toISOString(),
    },
  };
}

// What everyone knows about a wave. Its composition stays hidden until
// scouted (M1 step 4).
export function waveView(wave: Wave) {
  return {
    id: wave.id,
    index: wave.index,
    front: wave.front,
    status: wave.status,
    threat: wave.threat,
    spawnAt: wave.spawnAt.toISOString(),
    spawn: wave.spawn,
    targetVillageId: wave.targetVillageId,
    // Each step: [q, r, ms after spawnAt when the horde enters that hex].
    path: wave.path?.map((step) => [step.q, step.r, step.atMs]) ?? null,
    arrivesAt: wave.arrivesAt?.toISOString() ?? null,
    endsAt: wave.endsAt?.toISOString() ?? null,
  };
}

export async function wavesView(client: DbClient, worldId: number) {
  return (await listActiveWaves(client, worldId)).map(waveView);
}

// Scout missions and their reports are shared with the whole group.
export function missionView(mission: ScoutMission) {
  return {
    id: mission.id,
    villageId: mission.villageId,
    waveId: mission.waveId,
    sent: mission.sent,
    status: mission.status,
    target: mission.target,
    departsAt: mission.departsAt.toISOString(),
    arrivesAt: mission.arrivesAt.toISOString(),
    returnsAt: mission.returnsAt.toISOString(),
    report: mission.report,
  };
}

export async function scoutingView(client: DbClient, worldId: number) {
  return (await listMissions(client, worldId)).map(missionView);
}

export function worldSummary(world: World) {
  return {
    id: world.id,
    name: world.name,
    status: world.status,
    inviteCode: world.inviteCode,
    speed: world.speed,
    maxPlayers: world.maxPlayers,
    hostAccountId: world.hostAccountId,
    startedAt: world.startedAt?.toISOString() ?? null,
  };
}

// Everything a member needs to render the world. Co-op: every member sees
// every village in full.
export async function worldView(client: DbClient, world: World) {
  const members = await listMembers(client, world.id);
  const villages = await listVillages(client, world.id);
  const waves = await wavesView(client, world.id);
  const scouting = await scoutingView(client, world.id);
  const map =
    world.status === 'lobby'
      ? null
      : { radius: world.radius, activeFronts: world.activeFronts, hexes: await loadHexes(client, world.id) };
  return {
    ...worldSummary(world),
    members: members.map((m) => ({ accountId: m.accountId, displayName: m.displayName })),
    villages: villages.map(villageView),
    waves,
    scouting,
    map,
  };
}
