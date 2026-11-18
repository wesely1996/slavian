import type { Bonuses } from '../sim/research.js';
import { ownerBonuses } from './armies.js';
import { unitSpeed } from '../sim/smithing.js';
// A forest has caught fire (field.json terraform burn): whatever is on the
// road and would enter it while it burns, a horde, an army, a caravan or
// settlers, finishes the hex it is crossing and goes round it to where it
// was going, or waits at its edge until it is out and keeps its road,
// whichever brings it there sooner. Headed straight into the fire, it goes
// round from the hex it came from: walking back to it first, except a
// horde, which never turns back but swerves on from there.
import type { GameData } from '../data/index.js';
import { listArmies, saveArmy, type Army } from '../db/armies.js';
import { listCaravans, saveCaravanRoute, type Caravan } from '../db/caravans.js';
import { listExpeditions, saveExpeditionRoute } from '../db/expeditions.js';
import { loadFort } from '../db/forts.js';
import { effectiveBonuses } from '../db/heroes.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { loadLand } from '../db/rivers.js';
import { loadShipyard } from '../db/shipyards.js';
import { loadVillage } from '../db/villages.js';
import { listActiveWaves, marchOnward } from '../db/waves.js';
import type { World } from '../db/worlds.js';
import { armySpeed, terrainRelief } from '../sim/armies.js';
import { hex, type Hex } from '../sim/hex.js';
import type { Land } from '../sim/land.js';
import { caravanRoute, reversedRoute, roadRoute, spliceRoute, withoutHalts } from '../sim/logistics.js';
import { supplySpeedFactor } from '../sim/supply.js';
import { rngFor, routeFrom, type PathStep } from '../sim/waves.js';
import { planAmbushes } from './camps.js';
import { scheduleEvent } from './events.js';
import { cancelPlans, planIntercepts } from './field.js';
import { planRaids } from './outposts.js';
import { holdForQuiet } from './waves.js';

// Whether a road timed from `origin` still has to enter `cell` before
// `until` (a step after `at`).
export function entersBefore(path: readonly PathStep[], origin: Date, at: Date, cell: Hex, until: Date): boolean {
  return path.some((s) => s.q === cell.q && s.r === cell.r && origin.getTime() + s.atMs > at.getTime() && origin.getTime() + s.atMs < until.getTime());
}

// The road from `elapsedMs` along `path` round the fire, or null (no way
// round). It finishes the hex it is crossing (spliceRoute); if that hex is
// on fire, it goes round from the one before: walking back to it, as long
// as it had gone on (`turnBack`), or, a horde, swerving on from it at once.
export function detour(path: readonly PathStep[], elapsedMs: number, cell: Hex, next: (from: Hex) => PathStep[] | null, turnBack = true): PathStep[] | null {
  let i = path.findIndex((step) => step.atMs >= elapsedMs);
  if (i < 0) i = path.length - 1;
  const ahead = path[i]!;
  if (ahead.q !== cell.q || ahead.r !== cell.r) {
    const onward = next({ q: ahead.q, r: ahead.r });
    return onward ? spliceRoute(path, elapsedMs, () => onward) : null;
  }
  if (i === 0) return null;
  const back = path[i - 1]!;
  const onward = next({ q: back.q, r: back.r });
  if (!onward) return null;
  const turnAt = turnBack ? elapsedMs + (elapsedMs - back.atMs) : elapsedMs;
  const before = turnBack ? path.slice(0, i) : path.slice(0, i - 1);
  return [...before, { q: back.q, r: back.r, atMs: turnAt }, ...onward.slice(1).map((step) => ({ q: step.q, r: step.r, atMs: turnAt + step.atMs }))];
}

// Its road kept, waiting in the hex before the fire until it is out
// (`untilMs`, timed like the road): it steps into the fire's hex as the
// fire dies. Headed into it already, it walks back to that hex to wait.
export function waitOut(path: readonly PathStep[], elapsedMs: number, cell: Hex, untilMs: number): PathStep[] {
  let i = path.findIndex((step) => step.atMs >= elapsedMs);
  if (i < 0) i = path.length - 1;
  const j = path.findIndex((step, k) => k >= i && step.q === cell.q && step.r === cell.r);
  if (j <= 0) return [...path];
  const before = path[j - 1]!;
  const stepMs = path[j]!.atMs - before.atMs;
  const back = before.atMs < elapsedMs ? elapsedMs + (elapsedMs - before.atMs) : before.atMs;
  const leaves = Math.max(back, untilMs - stepMs);
  const shift = leaves + stepMs - path[j]!.atMs;
  return [...path.slice(0, j), { q: before.q, r: before.r, atMs: leaves }, ...path.slice(j).map((step) => ({ ...step, atMs: step.atMs + shift }))];
}

// Round the fire or waiting it out, whichever arrives sooner.
export function bestWay(path: readonly PathStep[], elapsedMs: number, cell: Hex, untilMs: number, next: (from: Hex) => PathStep[] | null, turnBack = true): PathStep[] {
  const waited = waitOut(path, elapsedMs, cell, untilMs);
  const around = detour(path, elapsedMs, cell, next, turnBack);
  return around && around.at(-1)!.atMs < waited.at(-1)!.atMs ? around : waited;
}

function safely(route: () => PathStep[]): PathStep[] | null {
  try {
    return route();
  } catch {
    return null;
  }
}

export async function avoidFire(client: DbClient, data: GameData, world: World, cell: Hex, until: Date, at: Date): Promise<void> {
  const land = await loadLand(client, world.id);
  // Hordes on the march: round it to their target.
  for (const wave of await listActiveWaves(client, world.id)) {
    if (wave.status !== 'marching' || !wave.path || !entersBefore(wave.path, wave.spawnAt, at, cell, until)) continue;
    const target = wave.targetVillageId !== null ? await loadVillage(client, wave.targetVillageId).catch(() => null) : null;
    const goal = target ? { id: target.id, cell: hex(target.q, target.r) } : { id: null, cell: hex(0, 0) };
    const sinceSpawn = at.getTime() - wave.spawnAt.getTime();
    const path = bestWay(
      wave.path,
      sinceSpawn,
      cell,
      until.getTime() - wave.spawnAt.getTime(),
      (from) => routeFrom(data, { terrain: land, from, targets: [goal], front: wave.front, composition: wave.composition, rng: rngFor(world.seed, wave.index, 0xf1), startMs: 0, worldSpeed: world.speed })?.path ?? null,
      false,
    );
    const march = holdForQuiet(world, wave.spawnAt, { path, arrivesAt: new Date(wave.spawnAt.getTime() + path.at(-1)!.atMs) });
    await marchOnward(client, wave.id, wave.targetVillageId, [...march.path], march.arrivesAt);
    await cancelPlans(client, world.id, wave.id);
    await scheduleEvent(client, world.id, march.arrivesAt, 'wave_arrive', { waveId: wave.id });
    await planRaids(client, data, world, wave.id, sinceSpawn);
    await planIntercepts(client, world, wave.id, sinceSpawn + 1);
  }
  // Armies on the road, out or coming home.
  for (const army of await listArmies(client, world.id, 0)) {
    if (army.status === 'marching' && entersBefore(army.path, army.departsAt, at, cell, until)) {
      const dest = hex(army.targetQ, army.targetR);
      const bonuses = await ownerBonuses(client, army);
      const path = bestWay(army.path, at.getTime() - army.departsAt.getTime(), cell, until.getTime() - army.departsAt.getTime(), (from) => safely(() => armyRoad(data, land, army, from, dest, at, world, bonuses)));
      const moved: Army = { ...army, path, arrivesAt: new Date(army.departsAt.getTime() + path.at(-1)!.atMs) };
      await saveArmy(client, moved);
      await scheduleEvent(client, world.id, moved.arrivesAt, 'army_arrive', { armyId: army.id });
    } else if (army.status === 'returning' && army.leavesAt) {
      const road = reversedRoute(army.path);
      if (!entersBefore(road, army.leavesAt, at, cell, until)) continue;
      const home = await loadVillage(client, army.homeVillageId).catch(() => null);
      if (!home) continue;
      const back = bestWay(road, at.getTime() - army.leavesAt.getTime(), cell, until.getTime() - army.leavesAt.getTime(), (from) => safely(() => armyRoad(data, land, army, from, hex(home.q, home.r), at, world, home.state.bonuses)));
      const moved: Army = { ...army, path: reversedRoute(back), returnsAt: new Date(army.leavesAt.getTime() + back.at(-1)!.atMs) };
      await saveArmy(client, moved);
      await scheduleEvent(client, world.id, moved.returnsAt!, 'army_return', { armyId: army.id });
    }
  }
  // Caravans, out or coming home.
  for (const caravan of await listCaravans(client, world.id, 0)) {
    const village = await loadVillage(client, caravan.villageId).catch(() => null);
    if (!village) continue;
    const bonuses = await effectiveBonuses(client, data, village);
    if (caravan.status === 'outbound' && entersBefore(caravan.path, caravan.departsAt, at, cell, until)) {
      const dest = await caravanGoal(client, caravan);
      const path = bestWay(caravan.path, at.getTime() - caravan.departsAt.getTime(), cell, until.getTime() - caravan.departsAt.getTime(), (from) => safely(() => caravanRoute(data, land, from, dest, world.speed, bonuses)));
      const arrivesAt = new Date(caravan.departsAt.getTime() + path.at(-1)!.atMs);
      const moved: Caravan = { ...caravan, path, arrivesAt, returnsAt: new Date(arrivesAt.getTime() + withoutHalts(path).at(-1)!.atMs) };
      await rerouteCaravan(client, data, world, moved, 'out', 'caravan_arrive', moved.arrivesAt, at);
    } else if (caravan.status === 'returning') {
      const road = reversedRoute(caravan.path);
      if (!entersBefore(road, caravan.arrivesAt, at, cell, until)) continue;
      const back = bestWay(road, at.getTime() - caravan.arrivesAt.getTime(), cell, until.getTime() - caravan.arrivesAt.getTime(), (from) => safely(() => caravanRoute(data, land, from, hex(village.q, village.r), world.speed, bonuses)));
      const moved: Caravan = { ...caravan, path: reversedRoute(back), returnsAt: new Date(caravan.arrivesAt.getTime() + back.at(-1)!.atMs) };
      await rerouteCaravan(client, data, world, moved, 'back', 'caravan_return', moved.returnsAt, at);
    }
  }
  // Settlers, on their way or walking home.
  for (const expedition of await listExpeditions(client, world.id, 0)) {
    const home = await loadVillage(client, expedition.villageId).catch(() => null);
    if (!home) continue;
    // At the settlers' pace, with their owner's forged harness.
    const settlerSpeed = unitSpeed(data, 'settler', home.state.bonuses);
    if (expedition.status === 'outbound' && entersBefore(expedition.path, expedition.departsAt, at, cell, until)) {
      const path = bestWay(expedition.path, at.getTime() - expedition.departsAt.getTime(), cell, until.getTime() - expedition.departsAt.getTime(), (from) =>
        safely(() => roadRoute(data, land, from, hex(expedition.q, expedition.r), settlerSpeed, world.speed)),
      );
      const arrivesAt = new Date(expedition.departsAt.getTime() + path.at(-1)!.atMs);
      const moved = { ...expedition, path, arrivesAt, returnsAt: new Date(arrivesAt.getTime() + withoutHalts(path).at(-1)!.atMs) };
      await saveExpeditionRoute(client, moved);
      await scheduleEvent(client, world.id, moved.arrivesAt, 'settlers_arrive', { expeditionId: expedition.id });
    } else if (expedition.status === 'returning') {
      const road = reversedRoute(expedition.path);
      if (!entersBefore(road, expedition.arrivesAt, at, cell, until)) continue;
      const back = bestWay(road, at.getTime() - expedition.arrivesAt.getTime(), cell, until.getTime() - expedition.arrivesAt.getTime(), (from) => safely(() => roadRoute(data, land, from, hex(home.q, home.r), settlerSpeed, world.speed)));
      const moved = { ...expedition, path: reversedRoute(back), returnsAt: new Date(expedition.arrivesAt.getTime() + back.at(-1)!.atMs) };
      await saveExpeditionRoute(client, moved);
      await scheduleEvent(client, world.id, moved.returnsAt, 'settlers_return', { expeditionId: expedition.id });
    }
  }
  await notifyWorld(client, { worldId: world.id, type: 'waves' });
  await notifyWorld(client, { worldId: world.id, type: 'armies' });
}

function armyRoad(data: GameData, land: Land, army: Army, from: Hex, to: Hex, at: Date, world: World, bonuses: Bonuses): PathStep[] {
  const fed = army.supply === null || army.supplyAt === null ? null : (army as Army & { supply: number; supplyAt: Date });
  const speed = armySpeed(data, army.units, bonuses) * supplySpeedFactor(data, fed, at, world.speed);
  return roadRoute(data, land, from, to, speed, world.speed, terrainRelief(data, army.units));
}

async function caravanGoal(client: DbClient, caravan: Caravan): Promise<Hex> {
  if (caravan.destinationFortId !== null) {
    const fort = await loadFort(client, caravan.destinationFortId);
    if (fort) return hex(fort.q, fort.r);
  }
  if (caravan.destinationShipyardId !== null) {
    const yard = await loadShipyard(client, caravan.destinationShipyardId);
    if (yard) return hex(yard.q, yard.r);
  }
  if (caravan.destinationVillageId !== null) {
    const village = await loadVillage(client, caravan.destinationVillageId).catch(() => null);
    if (village) return hex(village.q, village.r);
  }
  return hex(0, 0);
}

// A caravan's new road: camps waiting on the old one wait in vain, those on
// the new one lie in wait.
async function rerouteCaravan(client: DbClient, data: GameData, world: World, caravan: Caravan, leg: 'out' | 'back', event: string, due: Date, at: Date): Promise<void> {
  await saveCaravanRoute(client, caravan);
  await client.query(
    `UPDATE scheduled_events SET status = 'done', processed_at = now(), error = 'superseded'
     WHERE world_id = $1 AND type = 'caravan_ambush' AND status = 'pending' AND payload @> $2::jsonb`,
    [world.id, JSON.stringify({ caravanId: caravan.id })],
  );
  await scheduleEvent(client, world.id, due, event, { caravanId: caravan.id });
  if (!caravan.ambush) await planAmbushes(client, data, world, caravan, leg, at);
}
