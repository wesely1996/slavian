// Cultists of Černobog (events.json ritual): a rare daily event. They camp
// and work a ritual; every soldier who falls fighting them brings its end
// nearer. Scattered in time, the ritual is broken; if it ends, the Avatar
// of Černobog rises where they stood and marches on the villages like a
// horde, a single foe as strong as a great one.
import type { GameData } from '../data/index.js';
import { deleteCamp, loadCamp, setCampEndsAt, type Camp } from '../db/camps.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { listVillages } from '../db/villages.js';
import { insertWave, lastWave, type Wave } from '../db/waves.js';
import { listMembers, type World } from '../db/worlds.js';
import { mapResources } from '../sim/resources.js';
import type { Front } from '../sim/mapgen.js';
import { achieveAll } from './achievements.js';
import { createCamp } from './camps.js';
import { bountyAt } from './eventOutcomes.js';
import { scheduleEvent } from './events.js';
import { tell } from './notices.js';
import { reward } from './onboarding.js';

const MS_PER_HOUR = 3_600_000;
const MS_PER_MINUTE = 60_000;

// Cultists gather: their ritual ends `hours` from now, unless they are scattered.
export async function startRitual(
  client: DbClient,
  data: GameData,
  world: World,
  plan: { cell: { q: number; r: number }; front: Front; guards: Record<string, number> },
  at: Date,
): Promise<Camp> {
  const endsAt = new Date(at.getTime() + (data.events.kinds.ritual.hours * MS_PER_HOUR) / world.speed);
  const camp = await createCamp(client, data, world, { kind: 'cultists', front: plan.front, q: plan.cell.q, r: plan.cell.r, units: plan.guards, waveId: null, endsAt }, at);
  await scheduleEvent(client, world.id, endsAt, 'map_event_end', { campId: camp.id });
  return camp;
}

// Soldiers fell fighting the cultists: the ritual ends the sooner.
export async function quickenRitual(client: DbClient, data: GameData, world: World, campId: number, endsAt: Date, fallen: number, at: Date): Promise<void> {
  if (fallen <= 0) return;
  const sooner = new Date(Math.max(at.getTime(), endsAt.getTime() - (fallen * data.events.kinds.ritual.minutesPerFallen * MS_PER_MINUTE) / world.speed));
  await setCampEndsAt(client, campId, sooner);
  await scheduleEvent(client, world.id, sooner, 'map_event_end', { campId });
}

// The ritual ends: the cultists are gone, and the Avatar rises in their place.
export async function ritualEnds(client: DbClient, data: GameData, world: World, campId: number, dueAt: Date): Promise<void> {
  const camp = await loadCamp(client, campId);
  if (!camp || camp.status !== 'active' || camp.kind !== 'cultists' || camp.endsAt?.getTime() !== dueAt.getTime()) return;
  await deleteCamp(client, camp.id);
  const rules = data.events.kinds.ritual;
  const levels = data.waves.threatLevels;
  // Like a bridge's errand, it goes as a band of the latest horde (one
  // horde to an index), on its own errand.
  const last = await lastWave(client, world.id);
  const wave = await insertWave(
    client,
    world.id,
    {
      index: last?.index ?? 0,
      front: camp.front as Front,
      spawnAt: dueAt,
      composition: { [rules.avatar]: 1 },
      threat: levels[levels.length - 1]!.name,
      stance: 'offensive',
    },
    false,
    last?.id ?? null,
    { kind: 'avatar', target: null, from: { q: camp.q, r: camp.r } },
  );
  await scheduleEvent(client, world.id, dueAt, 'wave_spawn', { waveId: wave.id });
  for (const member of await listMembers(client, world.id)) {
    await tell(client, world, member.accountId, {
      kind: 'event',
      tier: 'push',
      title: 'The Avatar of Černobog walks at ({q}, {r})',
      body: 'The ritual is done. The Black God takes flesh and marches on the villages. Slay it for a great bounty.',
      vars: { q: camp.q, r: camp.r },
    }, dueAt);
  }
  await achieveAll(client, data, world, 'avatar_risen', dueAt);
  await notifyWorld(client, { worldId: world.id, type: 'waves' });
  await notifyWorld(client, { worldId: world.id, type: 'world' });
}

// A horde is over: if it was the Avatar and it was beaten, every member
// gets the great bounty.
export async function avatarEnds(client: DbClient, data: GameData, world: World, wave: Wave, status: string, at: Date): Promise<void> {
  if (wave.errand?.kind !== 'avatar' || status !== 'defeated') return;
  const bounty = bountyAt(data, world, at);
  const factor = data.events.kinds.ritual.avatarBountyFactor;
  const great = mapResources((k) => Math.round(bounty[k] * factor));
  const owners = new Set((await listVillages(client, world.id)).filter((v) => !v.ruin && v.ownerAccountId !== null).map((v) => v.ownerAccountId!));
  for (const member of await listMembers(client, world.id)) {
    if (owners.has(member.accountId)) await reward(client, world, member.accountId, great, at);
    await tell(client, world, member.accountId, {
      kind: 'event',
      tier: 'push',
      title: 'The Avatar of Černobog is slain',
      body: 'Its flesh falls to ash. Every village of the group gets {bounty} resources.',
      vars: { bounty: Object.values(great).reduce((a, b) => a + b, 0) },
    }, at);
  }
  await achieveAll(client, data, world, 'avatar_slain', at);
}
