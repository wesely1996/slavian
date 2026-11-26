// The gods' blessings (events.json blessings), once per world, for
// everyone: the water god's for a long river line the players dug, the
// forge god's for a unit forged to the last level of every line. Each
// makes the North hate the more, for good.
import type { GameData } from '../data/index.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { listRiverEdges } from '../db/rivers.js';
import { blessingCount, getWorld, listMembers, loadHexes, saveBlessings, type Blessings, type World } from '../db/worlds.js';
import { longestRiver } from '../sim/blessings.js';
import type { Front } from '../sim/mapgen.js';
import { tell } from './notices.js';

export type God = 'water' | 'forge';

const NOTICES: Record<God, { title: string; body: string }> = {
  water: {
    title: "The water god's blessing",
    body: 'The rivers you dug run long and the waters are pleased: along every river, armies, caravans and scouts travel twice as fast. The North hates you the more for it.',
  },
  forge: {
    title: "The forge god's blessing",
    body: 'A unit forged to the last of every craft: the forge god is pleased. Forging costs half and takes half as long for everyone. The North hates you the more for it.',
  },
};

// The hatred a front's every horde takes for good: the North's, for each blessing.
export function lastingHatred(data: GameData, world: Pick<World, 'blessings'>, front: Front): number {
  return front === 'north' ? blessingCount(world) * data.events.blessings.northHatred : 0;
}

// The world is blessed by `god`, if it isn't yet: everyone is told.
async function bless(client: DbClient, data: GameData, world: World, god: God, blessings: Blessings, at: Date): Promise<void> {
  if (blessings[god]) return;
  await saveBlessings(client, world.id, { ...blessings, [god]: at.toISOString() });
  for (const member of await listMembers(client, world.id)) {
    await tell(client, world, member.accountId, { kind: 'event', tier: 'push', title: NOTICES[god].title, body: NOTICES[god].body, vars: {} }, at);
  }
  await notifyWorld(client, { worldId: world.id, type: 'world' });
}

// A river dug: the longest line the players have dug, and the water god's
// blessing once it is long enough.
export async function riverDug(client: DbClient, data: GameData, worldId: number, at: Date): Promise<void> {
  const world = await getWorld(client, worldId);
  const terrain = new Map((await loadHexes(client, world.id)).map(([q, r, t]) => [`${q},${r}`, t] as const));
  const dug = (await listRiverEdges(client, world.id)).filter((e) => e.dug);
  const line = longestRiver(dug, terrain);
  const blessings = { ...world.blessings, riverLine: Math.max(line, world.blessings.riverLine ?? 0) };
  await saveBlessings(client, world.id, blessings);
  if (line >= data.events.blessings.water.riverLine) await bless(client, data, world, 'water', blessings, at);
}

// A unit forged to the last level of every line: the forge god's blessing.
export async function unitSmithedOut(client: DbClient, data: GameData, worldId: number, at: Date): Promise<void> {
  const world = await getWorld(client, worldId);
  await bless(client, data, world, 'forge', world.blessings, at);
}
