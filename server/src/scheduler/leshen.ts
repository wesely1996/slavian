// The Leshen, the wrath of nature (events.json leshen): a forest a player
// sets alight may wake him. He rises from the ashes with monsters of the
// North and marches like the Avatar of Černobog: on the nearest village
// first, razing whatever he beats, every player village before the Holy
// City, never making camp. Slaying his whole host brings a great bounty.
import type { GameData } from '../data/index.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { listVillages } from '../db/villages.js';
import { insertWave, lastWave, type Wave } from '../db/waves.js';
import { addEmbers, listMembers, type World } from '../db/worlds.js';
import type { Hex } from '../sim/hex.js';
import { mapResources } from '../sim/resources.js';
import { createRng } from '../sim/rng.js';
import { composeWave } from '../sim/waves.js';
import { bountyAt } from './eventOutcomes.js';
import { scheduleEvent } from './events.js';
import { tell } from './notices.js';
import { angerFront } from './waves.js';
import { reward } from './onboarding.js';

// The roll for a fire burnt out on `cell` at `at`: seeded by the world, the
// hex and the minute, so the solo engine rolls alike.
export function leshenSeed(world: World, cell: Hex, at: Date): number {
  return (world.seed ^ Math.imul(cell.q + 0x3c1, 0x45d9f3b) ^ Math.imul(cell.r + 0x7f1, 0x27d4eb2d) ^ Math.floor(at.getTime() / 60_000)) >>> 0;
}

// A forest a player set alight has burnt out on `cell`: maybe the Leshen wakes.
export async function maybeLeshen(client: DbClient, data: GameData, world: World, cell: Hex, at: Date): Promise<void> {
  const seed = leshenSeed(world, cell, at);
  if (createRng(seed)() < data.events.leshen.chance) await leshenRises(client, data, world, cell, at, seed);
}

// The Leshen rises on `cell` with his host, and marches.
export async function leshenRises(client: DbClient, data: GameData, world: World, cell: Hex, at: Date, seed: number): Promise<void> {
  const rules = data.events.leshen;
  const members = await listMembers(client, world.id);
  const levels = data.waves.threatLevels;
  // Like the Avatar, he goes as a band of the latest horde, on his own errand.
  const last = await lastWave(client, world.id);
  const index = last?.index ?? 0;
  const minions = composeWave(data, 'north', Math.max(1, index), rules.minions, seed, Math.max(1, members.length));
  const wave = await insertWave(
    client,
    world.id,
    {
      index,
      front: 'north',
      spawnAt: at,
      composition: { [rules.unit]: 1, ...minions },
      threat: levels[levels.length - 1]!.name,
      stance: 'offensive',
    },
    false,
    last?.id ?? null,
    { kind: 'leshen', target: null, from: { q: cell.q, r: cell.r } },
  );
  await scheduleEvent(client, world.id, at, 'wave_spawn', { waveId: wave.id });
  for (const member of members) {
    await tell(client, world, member.accountId, {
      kind: 'event',
      tier: 'push',
      title: 'The Leshen rises from the ashes at ({q}, {r})',
      body: 'The burnt forest wakes its lord. The wrath of nature marches on the villages with the beasts of the North. Slay his host for a great bounty.',
      vars: { q: cell.q, r: cell.r },
    }, at);
  }
  await notifyWorld(client, { worldId: world.id, type: 'waves' });
  await notifyWorld(client, { worldId: world.id, type: 'world' });
}

// A horde is over: if it was the Leshen's host and it was beaten, every
// member gets the great bounty, the player whose village or army felled it
// (`victor`) Svarog's Embers, and the North hates the more.
export async function leshenEnds(client: DbClient, data: GameData, world: World, wave: Wave, status: string, at: Date, victor: number | null): Promise<void> {
  if (wave.errand?.kind !== 'leshen' || status !== 'defeated') return;
  const rules = data.events.leshen;
  if (rules.embers > 0) await addEmbers(client, world.id, victor, rules.embers);
  await angerFront(client, data, world, 'north', rules.hatred, at);
  const bounty = bountyAt(data, world, at);
  const great = mapResources((k) => Math.round(bounty[k] * data.events.leshen.bountyFactor));
  const owners = new Set((await listVillages(client, world.id)).filter((v) => !v.ruin && v.ownerAccountId !== null).map((v) => v.ownerAccountId!));
  for (const member of await listMembers(client, world.id)) {
    if (owners.has(member.accountId)) await reward(client, world, member.accountId, great, at);
    await tell(client, world, member.accountId, {
      kind: 'event',
      tier: 'push',
      title: 'The Leshen is felled',
      body: 'The wrath of nature sinks back into the earth. Every village of the group gets {bounty} resources, and the North rages at his fall.',
      vars: { bounty: Object.values(great).reduce((a, b) => a + b, 0) },
    }, at);
  }
}
