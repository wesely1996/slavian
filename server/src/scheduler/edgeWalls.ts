// Walls along hex edges on the scheduler (data/field.json edgeWalls): a
// village raises one (or a gatehouse) tier by tier; standing, nobody crosses
// it but the players' own through a gatehouse. A horde planning its road
// weighs tearing one down against going round (sim/waves.ts routeFrom); one
// that tears it down (wall_breach, when it is through) leaves no wall. A
// wall finished in a marching horde's way makes it plan its road again.
import { z } from 'zod';
import type { GameData } from '../data/index.js';
import { bankSide, deleteEdgeWall, edgeWallAt, insertEdgeWall, listEdgeWalls, saveEdgeWall, type EdgeWall, type EdgeWallKind, type WallSide } from '../db/edgeWalls.js';
import { listForts } from '../db/forts.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { loadLand, riverEdge } from '../db/rivers.js';
import { loadVillage, saveVillageState } from '../db/villages.js';
import { listActiveWaves, loadWave, marchOnward, type Wave } from '../db/waves.js';
import type { World } from '../db/worlds.js';
import { RuleError } from '../errors.js';
import { wallsCrossed, wallTierCost, wallTierSeconds } from '../sim/edgeWalls.js';
import { inFortZone } from '../sim/forts.js';
import { hex, hexDistance, hexKey, neighbors, type Hex } from '../sim/hex.js';
import { edgeKey } from '../sim/land.js';
import { spliceRoute } from '../sim/logistics.js';
import { spend } from '../sim/resources.js';
import { rngFor, routeFrom } from '../sim/waves.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';
import { cancelPlans, planIntercepts } from './field.js';
import { tell } from './notices.js';
import { planRaids } from './outposts.js';
import { holdForQuiet } from './waves.js';

const THROUGH = new Set<Wave['status']>(['marching', 'battling', 'arrived', 'razing']);

export const edgeWallPayload = z.object({ aq: z.number().int(), ar: z.number().int(), bq: z.number().int(), br: z.number().int(), side: z.union([z.literal(0), z.literal(1), z.literal(2)]).default(0) });
export const wallBreachPayload = edgeWallPayload.extend({ waveId: z.number().int() });

function ends(w: { a: Hex; b: Hex; side: WallSide }): { aq: number; ar: number; bq: number; br: number; side: WallSide } {
  return { aq: w.a.q, ar: w.a.r, bq: w.b.q, br: w.b.r, side: w.side };
}

// Which side of a|b a wall built (or torn down) from `bank` stands on: a
// river edge holds one on each bank, a dry edge one along it.
async function sideFor(client: DbClient, worldId: number, a: Hex, b: Hex, bank: Hex | null): Promise<WallSide> {
  return (await riverEdge(client, worldId, a, b)) ? bankSide(a, b, bank ?? a) : 0;
}

// Raises a wall (or a gatehouse) along the edge a|b from `villageId`: the
// first tier, or the next on one standing. Along a river, it stands on the
// bank of `bank` (a, unless b is given).
export async function buildEdgeWall(client: DbClient, data: GameData, world: World, villageId: number, a: Hex, b: Hex, kind: EdgeWallKind, at: Date, bank: Hex | null = null): Promise<EdgeWall> {
  const rules = data.field.edgeWalls;
  const village = await loadVillage(client, villageId);
  if (village.ruin) throw new RuleError('A ruin raises no walls');
  const home = hex(village.q, village.r);
  if (hexDistance(a, b) !== 1) throw new RuleError('A wall runs between two neighbouring hexes');
  if (Math.min(hexDistance(a, home), hexDistance(b, home)) > rules.range) {
    const forts = await listForts(client, world.id);
    if (!inFortZone(data, forts, village.id, a) && !inFortZone(data, forts, village.id, b)) {
      throw new RuleError(`Walls go within ${rules.range} hexes of the village or in its forts' zones`);
    }
  }
  const land = await loadLand(client, world.id);
  for (const end of [a, b]) {
    const type = land.get(hexKey(end));
    if (!type || data.terrain.terrain[type].moveCost === null) throw new RuleError('No wall can stand there');
  }
  const side = await sideFor(client, world.id, a, b, bank);
  const existing = await edgeWallAt(client, world.id, a, b, side);
  if (existing && existing.kind !== kind) throw new RuleError(existing.kind === 'gate' ? 'A gatehouse stands there' : 'A wall stands there');
  if (existing && existing.ownerAccountId !== village.ownerAccountId) throw new RuleError('That wall is not yours');
  if (existing?.status === 'building' || existing?.status === 'upgrading') throw new RuleError('That wall is being raised');
  if (existing && existing.tier >= rules.tiers.length) throw new RuleError('That wall is as strong as it gets');
  const tier = existing ? existing.tier + 1 : 1;
  await saveVillageState(client, village.id, { ...village.state, ledger: spend(village.state.ledger, at, wallTierCost(data, kind, tier)) });
  const completesAt = new Date(at.getTime() + (wallTierSeconds(data, kind, tier) * 1000) / world.speed);
  if (existing) await saveEdgeWall(client, world.id, { ...existing, status: 'upgrading', builtBy: village.id, completesAt });
  else await insertEdgeWall(client, world.id, { a, b, kind, builtBy: village.id, ownerAccountId: village.ownerAccountId, completesAt, side });
  await scheduleEvent(client, world.id, completesAt, 'edge_wall_built', ends({ a, b, side }));
  await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
  await notifyWorld(client, { worldId: world.id, type: 'world' });
  return (await edgeWallAt(client, world.id, a, b, side))!;
}

// Tears down a wall of the village's owner along a|b (on the bank of
// `bank`, along a river); nothing comes back.
export async function tearDownEdgeWall(client: DbClient, world: World, villageId: number, a: Hex, b: Hex, bank: Hex | null = null): Promise<void> {
  const village = await loadVillage(client, villageId);
  const side = await sideFor(client, world.id, a, b, bank);
  const wall = await edgeWallAt(client, world.id, a, b, side);
  if (!wall) throw new RuleError('No wall stands there');
  if (wall.ownerAccountId !== village.ownerAccountId) throw new RuleError('That wall is not yours');
  await deleteEdgeWall(client, world.id, a, b, side);
  await notifyWorld(client, { worldId: world.id, type: 'world' });
}

// A horde has set out (or set out again `fromMs` into its march): a breach
// planned for every wall on the rest of its road, for when it is through.
export async function planBreaches(client: DbClient, world: World, wave: Wave, fromMs: number): Promise<void> {
  if (!wave.path) return;
  const walls = new Map<string, EdgeWall[]>();
  for (const w of await listEdgeWalls(client, world.id)) {
    if (w.status !== 'building') walls.set(edgeKey(w.a, w.b), [...(walls.get(edgeKey(w.a, w.b)) ?? []), w]);
  }
  for (const { key, atMs } of wallsCrossed(wave.path, walls, fromMs)) {
    // Every wall on the edge (one on each bank of a river) comes down.
    for (const wall of walls.get(key)!) {
      const payload = { waveId: wave.id, ...ends(wall) };
      const { rows } = await client.query(
        `SELECT 1 FROM scheduled_events WHERE world_id = $1 AND type = 'wall_breach' AND status = 'pending' AND payload @> $2::jsonb`,
        [world.id, JSON.stringify(payload)],
      );
      if (rows.length) continue;
      await scheduleEvent(client, world.id, new Date(wave.spawnAt.getTime() + atMs), 'wall_breach', payload);
    }
  }
}

// A wall finished (or raised a tier) across a marching horde's road: it
// plans its road again from the hex it is heading for, through the wall or
// round it.
async function avoidWall(client: DbClient, data: GameData, world: World, key: string, at: Date): Promise<void> {
  const land = await loadLand(client, world.id);
  for (const wave of await listActiveWaves(client, world.id)) {
    if (wave.status !== 'marching' || !wave.path) continue;
    const sinceSpawn = at.getTime() - wave.spawnAt.getTime();
    if (!wallsCrossed(wave.path, new Map([[key, true]]), sinceSpawn).length) continue;
    const target = wave.targetVillageId !== null ? await loadVillage(client, wave.targetVillageId).catch(() => null) : null;
    const goal = target ? { id: target.id, cell: hex(target.q, target.r) } : { id: null, cell: hex(0, 0) };
    let failed = false;
    const path = spliceRoute(wave.path, sinceSpawn, (from) => {
      const route = routeFrom(data, { terrain: land, from, targets: [goal], front: wave.front, composition: wave.composition, rng: rngFor(world.seed, wave.index, 0xe1), startMs: 0, worldSpeed: world.speed });
      if (!route) failed = true;
      return route?.path ?? [{ q: from.q, r: from.r, atMs: 0 }];
    });
    if (failed) continue;
    const march = holdForQuiet(world, wave.spawnAt, { path, arrivesAt: new Date(wave.spawnAt.getTime() + path.at(-1)!.atMs) });
    await marchOnward(client, wave.id, wave.targetVillageId, [...march.path], march.arrivesAt);
    await cancelPlans(client, world.id, wave.id);
    await scheduleEvent(client, world.id, march.arrivesAt, 'wave_arrive', { waveId: wave.id });
    await planRaids(client, data, world, wave.id, sinceSpawn);
    await planIntercepts(client, world, wave.id, sinceSpawn + 1);
  }
}

// The gatehouse of the fort's owner standing on an edge of its hex, if any
// (the strongest): merged with the fort as its outermost wall ring
// (sim/edgeWalls.ts GATE_RING).
export async function fortGatehouse(client: DbClient, worldId: number, cell: Hex, ownerAccountId: number | null): Promise<EdgeWall | null> {
  const around = new Set(neighbors(cell).map((n) => edgeKey(cell, n)));
  const gates = (await listEdgeWalls(client, worldId)).filter(
    (w) => w.kind === 'gate' && w.status !== 'building' && w.ownerAccountId === ownerAccountId && around.has(edgeKey(w.a, w.b)),
  );
  return gates.sort((x, y) => y.tier - x.tier)[0] ?? null;
}

// Whether the wall along a|b is a gatehouse merged with a standing fort of
// its owner's on one of its hexes (that fort's battle batters it).
async function mergedWithFort(client: DbClient, worldId: number, wall: EdgeWall): Promise<boolean> {
  if (wall.kind !== 'gate') return false;
  const keys = new Set([hexKey(wall.a), hexKey(wall.b)]);
  return (await listForts(client, worldId)).some((f) => f.kind === 'fort' && f.status === 'standing' && f.ownerAccountId === wall.ownerAccountId && keys.has(hexKey(hex(f.q, f.r))));
}

// A fort's battle battered its gatehouse down: a tier lower, or gone.
export async function breachGatehouse(client: DbClient, worldId: number, a: Hex, b: Hex, side: WallSide = 0): Promise<void> {
  const wall = await edgeWallAt(client, worldId, a, b, side);
  if (!wall) return;
  if (wall.tier <= 1) await deleteEdgeWall(client, worldId, a, b, side);
  else await saveEdgeWall(client, worldId, { ...wall, tier: wall.tier - 1, ...(wall.status === 'upgrading' ? { status: 'standing', completesAt: null } : {}) });
  await notifyWorld(client, { worldId, type: 'world' });
}

export const edgeWallHandlers: HandlerRegistry = {
  async edge_wall_built({ client, data, world }, event) {
    const { aq, ar, bq, br, side } = edgeWallPayload.parse(event.payload);
    const wall = await edgeWallAt(client, world.id, hex(aq, ar), hex(bq, br), side);
    if (!wall || wall.status === 'standing' || wall.completesAt?.getTime() !== event.dueAt.getTime()) return;
    await saveEdgeWall(client, world.id, { ...wall, tier: wall.tier + 1, status: 'standing', completesAt: null });
    await avoidWall(client, data, world, edgeKey(wall.a, wall.b), event.dueAt);
    await notifyWorld(client, { worldId: world.id, type: 'world' });
    await notifyWorld(client, { worldId: world.id, type: 'waves' });
  },

  // A horde through a wall on its road: it tore the wall down.
  async wall_breach({ client, world }, event) {
    const { waveId, aq, ar, bq, br, side } = wallBreachPayload.parse(event.payload);
    const wave = await loadWave(client, waveId);
    // A horde that turned since had its breaches called off (cancelPlans);
    // one through it may already be at its target, the same moment.
    if (!THROUGH.has(wave.status)) return;
    const wall = await edgeWallAt(client, world.id, hex(aq, ar), hex(bq, br), side);
    if (!wall || wall.status === 'building' || (await mergedWithFort(client, world.id, wall))) return;
    await deleteEdgeWall(client, world.id, wall.a, wall.b, side);
    await notifyWorld(client, { worldId: world.id, type: 'world' });
    await tell(client, world, wall.ownerAccountId, {
      kind: 'outpost_raided',
      tier: 'push',
      title: wall.kind === 'gate' ? 'A horde broke down your gatehouse' : 'A horde tore down your wall',
      body: 'Between ({aq}, {ar}) and ({bq}, {br}).',
      vars: { aq: wall.a.q, ar: wall.a.r, bq: wall.b.q, br: wall.b.r },
    }, event.dueAt);
  },
};
