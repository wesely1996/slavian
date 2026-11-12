// The Kalinov Bridge's quests in the world (data/bridge.json questPlaces):
// when a stage opens, its quests raise their own ruin, lair or host; while
// a stage is raised, every front sends a small horde at the builders.
import type { GameData } from '../data/index.js';
import { findBridge } from '../db/bridges.js';
import { insertQuestSite } from '../db/sites.js';
import { listVillages } from '../db/villages.js';
import { insertWave, lastWave, type Wave } from '../db/waves.js';
import { getWorld, listMembers, loadHexes, type World } from '../db/worlds.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { constructionSize, constructionTargets, questCell, type BridgeState } from '../sim/bridge.js';
import type { Front } from '../sim/mapgen.js';
import { composeWave, threatOf } from '../sim/waves.js';
import { createCamp, occupiedHexes } from './camps.js';
import { scheduleEvent } from './events.js';
import { tell } from './notices.js';

const MS_PER_HOUR = 3_600_000;

function stageSeed(world: World, stage: number, salt: number): number {
  return (world.seed ^ Math.imul(stage + 1, 0x9e3779b1) ^ salt) >>> 0;
}

async function tellAll(client: DbClient, world: World, title: string, body: string, vars: Record<string, string | number>, at: Date): Promise<void> {
  for (const member of await listMembers(client, world.id)) {
    await tell(client, world, member.accountId, { kind: 'bridge', tier: 'push', title, body, vars }, at);
  }
}

// The horde number quest hosts and builders' raiders are drawn as (the
// latest so far), and the horde they count as breaking away from.
async function lastHorde(client: DbClient, worldId: number): Promise<Wave | null> {
  return lastWave(client, worldId);
}

// A stage opens (`stage`, 0-based): its quests raise their places and host.
export async function openStage(client: DbClient, data: GameData, world: World, stage: number, at: Date): Promise<void> {
  const def = data.bridge.stages[stage];
  if (!def) return;
  const places = data.bridge.questPlaces;
  const players = (await listMembers(client, world.id)).length;
  const last = await lastHorde(client, world.id);
  const index = Math.max(1, last?.index ?? 1);
  for (const quest of def.quests) {
    if (quest.kind === 'relic' || quest.kind === 'grove') {
      const place = places[quest.kind];
      const terrain = new Map((await loadHexes(client, world.id)).map(([q, r, t]) => [`${q},${r}`, t] as const));
      const cell = questCell(data, terrain, await occupiedHexes(client, world.id), stageSeed(world, stage, quest.kind === 'relic' ? 0x5e1 : 0x6a7), place.minDistance, place.maxDistance);
      if (!cell) continue;
      const units = composeWave(data, place.front as Front, index, place.units, stageSeed(world, stage, 0x7c3), players);
      if (quest.kind === 'relic') {
        await insertQuestSite(client, world.id, { kind: places.relic.siteKind, q: cell.q, r: cell.r, guardians: units }, 'relic');
      } else {
        await createCamp(client, data, world, { kind: 'lair', front: place.front, q: cell.q, r: cell.r, units, waveId: last?.id ?? null, quest: 'grove' }, at);
      }
      await tellAll(client, world, '{place} rises', '{story} It is marked on the map at ({q}, {r}).', { place: place.name, story: quest.story, q: cell.q, r: cell.r }, at);
      await notifyWorld(client, { worldId: world.id, type: 'world' });
    }
    if (quest.kind === 'defense') {
      await sendQuestArmy(client, data, world, stage, new Date(at.getTime() + (places.defense.delayHours * MS_PER_HOUR) / world.speed));
      await tellAll(client, world, '{place} gather', '{story}', { place: places.defense.name, story: quest.story }, at);
    }
  }
}

// The quest's host sets out at `spawnAt` from a front of its own and
// marches on the Holy City.
export async function sendQuestArmy(client: DbClient, data: GameData, world: World, stage: number, spawnAt: Date): Promise<void> {
  const last = await lastHorde(client, world.id);
  if (!last) return;
  const fronts = world.activeFronts;
  const front = fronts[(stage + last.id) % fronts.length]! as Front;
  const players = (await listMembers(client, world.id)).length;
  const composition = composeWave(data, front, Math.max(1, last.index), data.bridge.questPlaces.defense.units, stageSeed(world, stage, last.id), players);
  const wave = await insertWave(
    client,
    world.id,
    { index: last.index, front, spawnAt, composition, threat: threatOf(data, composition), stance: 'offensive' },
    false,
    last.id,
    { kind: 'quest', target: null },
  );
  await scheduleEvent(client, world.id, spawnAt, 'wave_spawn', { waveId: wave.id });
  await notifyWorld(client, { worldId: world.id, type: 'waves' });
}

// A stage starts to be raised: every active front sends a small horde, each
// at its own target (the group's villages, then the Holy City).
export async function sendConstructionRaids(client: DbClient, data: GameData, world: World, bridge: BridgeState, at: Date): Promise<void> {
  const last = await lastHorde(client, world.id);
  if (!last) return;
  const villages = (await listVillages(client, world.id)).filter((v) => !v.ruin && v.ownerAccountId !== null).map((v) => v.id);
  const fronts = world.activeFronts;
  const targets = constructionTargets(fronts, villages);
  const players = (await listMembers(client, world.id)).length;
  for (const [i, front] of fronts.entries()) {
    const composition = composeWave(data, front as Front, Math.max(1, last.index), constructionSize(data, bridge.stage), stageSeed(world, bridge.stage, 0xb00 + i), players);
    const wave = await insertWave(
      client,
      world.id,
      { index: last.index, front: front as Front, spawnAt: at, composition, threat: threatOf(data, composition), stance: 'offensive' },
      false,
      last.id,
      { kind: 'bridge', target: targets[i]! },
    );
    await scheduleEvent(client, world.id, at, 'wave_spawn', { waveId: wave.id });
  }
  await tellAll(client, world, 'Nav strikes at the builders', 'While {stage} is raised, every front sends a band at a different target.', { stage: data.bridge.stages[bridge.stage]!.name }, at);
  await notifyWorld(client, { worldId: world.id, type: 'waves' });
}

// A horde on an errand is over: the quest's host, beaten, answers its
// quest; not beaten, another comes later while the stage still wants it.
export async function afterErrand(client: DbClient, data: GameData, world: World, wave: Wave, status: string, at: Date): Promise<boolean> {
  if (wave.errand?.kind !== 'quest') return false;
  if (status === 'defeated') return true;
  const bridge = await findBridge(client, world.id);
  const stage = bridge && bridge.status === 'open' ? data.bridge.stages[bridge.stage] : null;
  if (!bridge || !stage?.quests.some((q) => q.kind === 'defense') || bridge.quests.defense) return false;
  if ((await getWorld(client, world.id)).status !== 'running') return false;
  await sendQuestArmy(client, data, world, bridge.stage, new Date(at.getTime() + (data.bridge.questPlaces.defense.retryHours * MS_PER_HOUR) / world.speed));
  return false;
}
