// Armies on the scheduler: army_arrive (station, join a battle, hold a hex,
// join a garrison, or turn back), army_return (home again), army_hunger
// (an army out of food losing men, or lost). Battles (battles.ts, field.ts)
// use the helpers here to fold armies into the defenders and to call in
// reinforcements. Armies carry their own grain (sim/supply.ts); armies from
// before that (supply null) are fed by their home village. Forts and supply
// points keep grain too: an army standing on one fills up from it as it
// would in a village, and can leave grain there.
import { combatants } from '../sim/scouting.js';
import { wagonsIn } from '../sim/field.js';
import { loadLand } from '../db/rivers.js';
import type { Land } from '../sim/land.js';
import { z } from 'zod';
import type { GameData, Stance, TerrainId } from '../data/index.js';
import { armiesAt, insertArmy, listArmies, loadArmy, saveArmy, setArmyLeaders, type Army, type ArmyPost } from '../db/armies.js';
import { addDefenders, loadBattle, type Battle } from '../db/battles.js';
import { heroWithArmy, loadHero, saveHero, type Hero } from '../db/heroes.js';
import { generalWithArmy, loadGeneral, saveGeneral, type General } from '../db/generals.js';
import { hallLevelAt, killGeneral } from './generals.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { listVillages, loadVillage, saveVillageState, type Village } from '../db/villages.js';
import { heroFactor } from '../sim/heroes.js';
import { loadWave, type Wave } from '../db/waves.js';
import { loadHexes, rallyPoint, type World } from '../db/worlds.js';
import type { TrainingBatch } from '../sim/training.js';
import { RuleError } from '../errors.js';
import { addUnits, approachAngle, armySpeed, fighters, joinBonus, terrainRelief, total, validateArmy, type ArmyOrders } from '../sim/armies.js';
import { hex, hexDistance, type Hex } from '../sim/hex.js';
import { woundMs } from '../sim/heroes.js';
import { reversedRoute, roadRoute, spliceRoute } from '../sim/logistics.js';
import type { PathStep } from '../sim/waves.js';
import { completeTraining, healFallen, healerChance, joinGarrison, leaveGarrison, loseAway, returnHome } from '../sim/village.js';
import { createRng } from '../sim/rng.js';
import { quarterOwed, quarterTickMs, settlementFloor, spareGrain, storeFloor } from '../sim/quarters.js';
import { addSupply, fullSupply, hungerStrikes, nextHungerCheck, outOfFoodAt, settleSupply, supplyLeft, supplyRoom, supplySpeedFactor, trimSupply, type Supplied } from '../sim/supply.js';
import { amountsAt, mapResources, spend, type Resources } from '../sim/resources.js';
import { receive } from '../sim/logistics.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';
import { tell } from './notices.js';
import { interceptAt } from './field.js';
import { deliverLoot, stormCamp } from './camps.js';
import { arriveAtSite } from './sites.js';
import { reachEdge } from './raids.js';
import { siteAt } from '../db/sites.js';
import { campAt } from '../db/camps.js';
import { fortAt, markFortManned, setFortGrain, type Fort } from '../db/forts.js';
import { listShipyards } from '../db/shipyards.js';
import { grainCapacity } from '../sim/field.js';

export const armyPayload = z.object({ armyId: z.number().int() });
export type ArmyPayload = z.infer<typeof armyPayload>;

// The world's land: terrain, and the rivers no one can cross yet.
export async function terrainOf(client: DbClient, worldId: number): Promise<Land> {
  return loadLand(client, worldId);
}

export interface ArmyOrder {
  homeVillageId: number;
  // A village to go to, or (with orders 'hold' or 'clear') a hex to hold or
  // a camp to clear.
  targetVillageId: number | null;
  targetHex?: Hex | undefined;
  units: Record<string, number>;
  orders: ArmyOrders;
  // The owner's hero, standing in the home village, leads it.
  withHero?: boolean | undefined;
  // One of the owner's generals at home in the village leads it.
  generalId?: number | undefined;
  // Its battle stance (absent: the village's).
  stance?: Stance | undefined;
  // It comes home by itself once its errand is done.
  returnHome?: boolean | undefined;
  at: Date;
}

// Sends troops from a village as an army.
export async function dispatchArmy(client: DbClient, data: GameData, world: World, input: ArmyOrder): Promise<Army> {
  const units = validateArmy(data, input.units, input.orders);
  const home = await loadVillage(client, input.homeVillageId);
  let to: Hex;
  if (input.orders === 'explore') {
    if (!input.targetHex) throw new RuleError('Say which site to explore');
    to = input.targetHex;
    const site = await siteAt(client, world.id, to.q, to.r);
    if (!site) throw new RuleError('There is no ancient site there');
    if (site.status === 'explored') throw new RuleError('That site has already been explored');
  } else if (input.orders === 'clear') {
    if (!input.targetHex) throw new RuleError('Say which camp to clear');
    to = input.targetHex;
    if (!(await campAt(client, world.id, to.q, to.r))) throw new RuleError('There is no camp there');
  } else if (input.orders === 'raid') {
    // To the map's edge (scheduler/raids.ts picks the hex).
    if (!input.targetHex) throw new RuleError('Say where they leave the map');
    to = input.targetHex;
  } else if (input.orders === 'hold') {
    if (!input.targetHex) throw new RuleError('Say which hex to hold');
    to = input.targetHex;
    const terrain = (await terrainOf(client, world.id)).get(`${to.q},${to.r}`);
    if (!terrain || data.terrain.terrain[terrain].moveCost === null) throw new RuleError('No army can stand there');
    if (hexDistance(to, hex(home.q, home.r)) === 0) throw new RuleError('That is the village itself');
  } else {
    if (input.targetVillageId === null || input.targetVillageId === home.id) throw new RuleError('Send them to another village');
    const target = await loadVillage(client, input.targetVillageId).catch(() => null);
    if (!target || target.worldId !== world.id) throw new RuleError('No such village in this world');
    if (input.orders === 'garrison' && target.ownerAccountId !== home.ownerAccountId) throw new RuleError('Troops only join the garrisons of your own villages');
    // Harassers strike a horde, never a friendly village: only where one
    // fights or marches on it.
    if (input.orders === 'harass') {
      const { rows } = await client.query(
        `SELECT 1 FROM battles WHERE village_id = $1 AND status = 'ongoing'
         UNION ALL SELECT 1 FROM waves WHERE target_village_id = $1 AND status IN ('marching', 'battling') LIMIT 1`,
        [target.id],
      );
      if (rows.length === 0) throw new RuleError(`No horde comes against ${target.name} to harass`);
    }
    to = hex(target.q, target.r);
  }
  // The troops leave the garrison with what grain the granary can spare
  // above the village's floor for armies.
  let state = leaveGarrison(data, home.state, units, input.at, world.speed);
  const grain = Math.min(fullSupply(data, units), villageSpare(data, state, input.at));
  if (grain > 0) state = { ...state, ledger: spend(state.ledger, input.at, grainOnly(grain)) };
  const supplied: Supplied = { units, supply: grain, supplyAt: input.at, hungrySince: null };
  const speed = armySpeed(data, units) * supplySpeedFactor(data, supplied, input.at, world.speed);
  const path = roadRoute(data, await terrainOf(client, world.id), hex(home.q, home.r), to, speed, world.speed, terrainRelief(data, units));

  let heroAccountId: number | null = null;
  if (input.withHero) {
    const hero = await loadHero(client, world.id, home.ownerAccountId!);
    if (hero.status !== 'home' || hero.villageId !== home.id) throw new RuleError(`${hero.name} is not ready in ${home.name}`);
    if (home.state.besieged) throw new RuleError(`${hero.name} won't leave in the middle of a battle`);
    heroAccountId = hero.accountId;
  }
  let generalId: number | null = null;
  if (input.generalId !== undefined) {
    const general = await loadGeneral(client, input.generalId).catch(() => null);
    if (!general || general.accountId !== home.ownerAccountId) throw new RuleError('No such general');
    if (general.status !== 'home' || general.villageId !== home.id) throw new RuleError(`${general.name} is not ready in ${home.name}`);
    if (home.state.besieged) throw new RuleError(`${general.name} won't leave in the middle of a battle`);
    generalId = general.id;
  }
  const army = await insertArmy(client, {
    worldId: world.id,
    ownerAccountId: home.ownerAccountId,
    homeVillageId: home.id,
    targetVillageId: ['hold', 'clear', 'explore', 'raid'].includes(input.orders) ? null : input.targetVillageId,
    supply: grain,
    supplyAt: input.at,
    targetQ: to.q,
    targetR: to.r,
    heroAccountId,
    generalId,
    orders: input.orders,
    stance: input.stance ?? home.state.stance,
    returnHome: input.returnHome ?? false,
    units,
    path,
    departsAt: input.at,
    arrivesAt: new Date(input.at.getTime() + path.at(-1)!.atMs),
  });
  if (heroAccountId !== null) {
    const hero = await loadHero(client, world.id, heroAccountId);
    await saveHero(client, { ...hero, status: 'with_army', villageId: null, armyId: army.id });
    await notifyWorld(client, { worldId: world.id, type: 'heroes' });
  }
  if (generalId !== null) {
    const general = await loadGeneral(client, generalId);
    await saveGeneral(client, { ...general, status: 'with_army', villageId: null, armyId: army.id });
    await notifyWorld(client, { worldId: world.id, type: 'generals' });
  }
  await saveVillageState(client, home.id, state);
  const payload: ArmyPayload = { armyId: army.id };
  await scheduleEvent(client, world.id, army.arrivesAt, 'army_arrive', payload);
  const fed = await planHunger(client, data, world, army, input.at);
  await notifyWorld(client, { worldId: world.id, type: 'village', villageId: home.id });
  await notifyWorld(client, { worldId: world.id, type: 'armies' });
  return fed;
}

// An army done with its errand stands on the hex it reached, holding it,
// until it is moved, sent into a settlement or called home.
export async function holdHex(client: DbClient, data: GameData, world: World, army: Army, at: Date): Promise<Army> {
  // Told to come home once done, it does.
  if (!(await staysOut(client, world, army))) return sendHome(client, world, army, at, data);
  const holding: Army = { ...army, status: 'stationed', orders: 'hold', targetVillageId: null, battleId: null };
  await saveArmy(client, holding);
  await interceptAt(client, data, world, hex(army.targetQ, army.targetR), at);
  return holding;
}

// Whether an army done with its errand stays where it is: always, unless
// it was told to come home once done; and even then while it guards a
// shipyard whose boat isn't finished (it comes home when the boat is).
export async function staysOut(client: DbClient, world: World, army: Army): Promise<boolean> {
  if (!army.returnHome) return true;
  if (army.targetVillageId !== null) return false;
  return (await listShipyards(client, world.id)).some((s) => s.q === army.targetQ && s.r === army.targetR && s.status !== 'done');
}

// Where a standing army goes next: a hex to hold, or a village (its owner's
// to join the garrison, another to support).
export async function moveArmy(
  client: DbClient,
  data: GameData,
  world: World,
  army: Army,
  // A village of its owner's: it joins the garrison there unless `join` is
  // false (then it stands there as an army). `orders` overrides what it
  // does there (an army answering a battle reinforces).
  to: { hex?: Hex | undefined; villageId?: number | undefined; join?: boolean | undefined; orders?: ArmyOrders | undefined },
  at: Date,
): Promise<Army> {
  // An army on the road can be turned too (not one in a battle).
  const onTheRoad = army.status === 'marching' || army.status === 'returning';
  if (!onTheRoad) standing(army);
  const here = hex(army.targetQ, army.targetR);
  let dest: Hex;
  let orders: ArmyOrders = 'hold';
  let targetVillageId: number | null = null;
  if (to.villageId !== undefined) {
    const village = await loadVillage(client, to.villageId).catch(() => null);
    if (!village || village.worldId !== world.id) throw new RuleError('No such village in this world');
    dest = hex(village.q, village.r);
    orders = to.orders ?? (village.ownerAccountId === army.ownerAccountId && to.join !== false ? 'garrison' : 'support');
    targetVillageId = village.id;
  } else {
    if (!to.hex) throw new RuleError('Say where they should go');
    dest = to.hex;
    const terrain = (await terrainOf(client, world.id)).get(`${dest.q},${dest.r}`);
    if (!terrain || data.terrain.terrain[terrain].moveCost === null) throw new RuleError('No army can stand there');
    if ((await listVillages(client, world.id)).some((v) => v.q === dest.q && v.r === dest.r)) throw new RuleError('That is a village; send them into it');
    // Sent onto a camp it storms it; onto a site not yet searched, it explores.
    orders = to.orders ?? (await ordersAt(client, data, world, army, dest));
  }
  if (!onTheRoad && dest.q === here.q && dest.r === here.r) {
    // Already standing in its owner's village: it joins the garrison now.
    if (orders === 'garrison') {
      await joinVillage(client, data, world, army, targetVillageId!, at);
      return loadArmy(client, army.id);
    }
    throw new RuleError('They are already there');
  }
  const land = await terrainOf(client, world.id);
  let path: PathStep[];
  let departsAt = at;
  if (onTheRoad) {
    // It finishes the hex it is crossing, then takes the new road; the road
    // it came by stays (one coming home turns on that road, backwards).
    const fed = supplied(army);
    const speed = armySpeed(data, army.units) * supplySpeedFactor(data, fed, at, world.speed);
    const road = army.status === 'returning' ? reversedRoute(army.path) : army.path;
    departsAt = army.status === 'returning' ? army.leavesAt! : army.departsAt;
    path = spliceRoute(road, at.getTime() - departsAt.getTime(), (from) => roadRoute(data, land, from, dest, speed, world.speed, terrainRelief(data, army.units)));
  } else {
    army = await setOff(client, data, world, army, at);
    const fed = supplied(army);
    const speed = armySpeed(data, army.units) * supplySpeedFactor(data, fed, at, world.speed);
    path = roadRoute(data, land, here, dest, speed, world.speed, terrainRelief(data, army.units));
  }
  const moving: Army = {
    ...army,
    orders,
    targetVillageId,
    targetQ: dest.q,
    targetR: dest.r,
    path,
    status: 'marching',
    battleId: null,
    wagonFortAt: null,
    departsAt,
    arrivesAt: new Date(departsAt.getTime() + path.at(-1)!.atMs),
    leavesAt: null,
    returnsAt: null,
  };
  await saveArmy(client, moving);
  await scheduleEvent(client, world.id, moving.arrivesAt, 'army_arrive', { armyId: army.id } satisfies ArmyPayload);
  return moving;
}

// What an army sent onto a hex does there: storm a camp, explore an
// ancient site nobody has searched yet, or hold it.
async function ordersAt(client: DbClient, data: GameData, world: World, army: Army, dest: Hex): Promise<ArmyOrders> {
  const fights = total(combatants(data, army.units)) > 0;
  if (await campAt(client, world.id, dest.q, dest.r)) {
    if (!fights) throw new RuleError('Scouts alone don\'t storm camps');
    return 'clear';
  }
  const site = await siteAt(client, world.id, dest.q, dest.r);
  return site && site.status !== 'explored' ? 'explore' : 'hold';
}

// Whether an army comes home by itself once its errand is done. Switched
// on for one standing with its errand done, it turns home now (one still
// searching a site or guarding an unfinished boat waits until it is done).
export async function setReturnHome(client: DbClient, data: GameData, world: World, army: Army, on: boolean, at: Date): Promise<Army> {
  if (army.status === 'returning' || army.status === 'done') throw new RuleError('They are already on their way home');
  if (!['support', 'hold', 'clear', 'explore'].includes(army.orders)) throw new RuleError('They come home by themselves');
  const next: Army = { ...army, returnHome: on };
  await saveArmy(client, next);
  const searching = army.orders === 'explore';
  if (on && army.status === 'stationed' && !searching && !(await staysOut(client, world, next))) return sendHome(client, world, next, at, data);
  return next;
}

function standing(army: Army): void {
  if (army.status === 'engaged') throw new RuleError('That army is in the middle of a battle');
  if (army.status !== 'stationed') throw new RuleError('Only armies standing still can be given these orders');
}

// A standing army disbanded: its troops go home to their farms, and
// whoever led it makes their own way home.
export async function disbandArmy(client: DbClient, data: GameData, world: World, army: Army, at: Date): Promise<Army> {
  standing(army);
  // Quartered, its place is paid for what it ate till now.
  army = await unquarter(client, data, world, army, at);
  const home = await loadVillage(client, army.homeVillageId);
  const land = await terrainOf(client, world.id);
  const here = hex(army.targetQ, army.targetR);
  const gone: Army = { ...army, units: {}, status: 'done', battleId: null, leavesAt: at, returnsAt: at, hungerAt: null };
  await saveArmy(client, gone);
  const hero = await heroWithArmy(client, army.id);
  if (hero) {
    const path = roadRoute(data, land, here, hex(home.q, home.r), data.heroes.speed * heroFactor(data, hero.kind, 'heroSpeed'), world.speed);
    const arrivesAt = new Date(at.getTime() + path.at(-1)!.atMs);
    await saveHero(client, { ...hero, status: 'traveling', villageId: home.id, armyId: null, path, departsAt: at, arrivesAt });
    await scheduleEvent(client, world.id, arrivesAt, 'hero_arrive', { accountId: hero.accountId });
    await notifyWorld(client, { worldId: world.id, type: 'heroes' });
  }
  const general = await generalWithArmy(client, army.id);
  if (general) {
    const path = roadRoute(data, land, here, hex(home.q, home.r), data.heroes.generals.speed, world.speed);
    const until = new Date(at.getTime() + path.at(-1)!.atMs);
    await saveGeneral(client, { ...general, status: 'traveling', villageId: home.id, armyId: null, path, departsAt: at, until });
    await scheduleEvent(client, world.id, until, 'general_arrive', { generalId: general.id });
    await notifyWorld(client, { worldId: world.id, type: 'generals' });
  }
  return gone;
}

// A standing army in a village, or on a fort or supply point, takes on
// what grain it can carry from its stores, down to the place's floor.
export async function resupplyArmy(client: DbClient, data: GameData, world: World, army: Army, at: Date): Promise<Army> {
  standing(army);
  const place = await placeOf(client, army);
  if (!place) throw new RuleError('They stand in no village, fort or supply point');
  if (!supplied(army)) throw new RuleError('Their village feeds them');
  const filled = await fillUp(client, data, world, army, place, at);
  return planHunger(client, data, world, filled, at);
}

// A standing army holding open ground draws its wagons into a ring: a
// wagon fort, ready after field.json wagonFort.setupMinutes (game minutes),
// until it moves.
export async function circleWagons(client: DbClient, data: GameData, world: World, army: Army, at: Date): Promise<Army> {
  standing(army);
  if (army.orders !== 'hold' || army.targetVillageId !== null) throw new RuleError('Only an army holding open ground circles its wagons');
  if (wagonsIn(data, army.units) === 0) throw new RuleError('They have no wagons');
  if (army.wagonFortAt) throw new RuleError('Their wagons are already in a ring');
  if (await fortAt(client, world.id, army.targetQ, army.targetR)) throw new RuleError('There is a fort or supply point there already');
  const ringed: Army = { ...army, wagonFortAt: new Date(at.getTime() + Math.round((data.field.wagonFort.setupMinutes * 60_000) / world.speed)) };
  await saveArmy(client, ringed);
  return ringed;
}

// A standing army on a fort or supply point leaves up to `grain` of its own
// supply in its stores (as much as it has, and as fits).
export async function stockStore(client: DbClient, data: GameData, world: World, army: Army, grain: number, at: Date): Promise<Army> {
  standing(army);
  const store = await storeHere(client, army);
  if (!store) throw new RuleError('They stand on no fort or supply point');
  const fed = supplied(army);
  if (!fed) throw new RuleError('Their village feeds them');
  const room = grainCapacity(data, store.kind) - store.grain;
  if (room <= 0) throw new RuleError('Its stores are full');
  const amount = Math.min(grain, supplyLeft(data, fed, at, world.speed), room);
  if (amount <= 0) throw new RuleError('They have no grain to spare');
  const settled = settleSupply(data, fed, at, world.speed);
  await setFortGrain(client, store.id, store.grain + amount);
  return planHunger(client, data, world, { ...settled, supply: settled.supply - amount }, at);
}

// The standing fort or supply point an army stands on, out in the field.
async function storeHere(client: DbClient, army: Army): Promise<Fort | null> {
  if (army.targetVillageId !== null || (army.status !== 'stationed' && army.status !== 'engaged')) return null;
  const fort = await fortAt(client, army.worldId, army.targetQ, army.targetR);
  return fort?.status === 'standing' ? fort : null;
}

// Where an army standing (or fighting) can be fed: the village it stands
// in, or the fort or supply point under it.
export type Place = { kind: 'village'; village: Village } | { kind: 'store'; fort: Fort };

export async function placeOf(client: DbClient, army: Army): Promise<Place | null> {
  if (army.status !== 'stationed' && army.status !== 'engaged') return null;
  if (army.targetVillageId !== null) {
    const village = await loadVillage(client, army.targetVillageId).catch(() => null);
    return village && !village.ruin ? { kind: 'village', village } : null;
  }
  const fort = await storeHere(client, army);
  return fort ? { kind: 'store', fort } : null;
}

// What grain a village can give armies at `at`: above its floor.
export function villageSpare(data: GameData, state: Village['state'], at: Date): number {
  return spareGrain(amountsAt(state.ledger, at).grain, settlementFloor(data, state.armyFloor, state.ledger.capacity.grain));
}

function placeSpare(data: GameData, place: Place, at: Date): number {
  return place.kind === 'village' ? villageSpare(data, place.village.state, at) : spareGrain(place.fort.grain, storeFloor(place.fort.armyFloor));
}

// Takes grain from a place's stores (no more than it can spare).
async function takeFromPlace(client: DbClient, world: World, place: Place, grain: number, at: Date): Promise<void> {
  if (grain <= 0) return;
  if (place.kind === 'store') {
    await setFortGrain(client, place.fort.id, place.fort.grain - grain);
    return;
  }
  const { village } = place;
  await saveVillageState(client, village.id, { ...village.state, ledger: spend(village.state.ledger, at, grainOnly(grain)) });
  await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
}

// An army at a place takes on what grain it can carry from its stores,
// down to the place's floor (not saved).
async function fillUp(client: DbClient, data: GameData, world: World, army: Army, place: Place, at: Date): Promise<Army> {
  const fed = supplied(army);
  if (!fed) return army;
  const grain = Math.min(supplyRoom(data, fed, at, world.speed), placeSpare(data, place, at));
  if (grain <= 0) return army;
  await takeFromPlace(client, world, place, grain, at);
  return addSupply(data, fed, grain, at, world.speed);
}

// A quartered army's place pays for what it ate since it was last charged
// (quarters.upkeep of its upkeep), down to its floor. A place that could
// not pay it all feeds it no more: from now it eats its own grain (not
// saved). An army no longer at a place is unquartered the same way.
export async function settleQuarters(client: DbClient, data: GameData, world: World, army: Army, at: Date): Promise<Army> {
  const fed = supplied(army);
  if (!fed || !army.quarteredAt) return army;
  const place = await placeOf(client, army);
  const owed = quarterOwed(data, army.units, army.quarteredAt, at, world.speed);
  const paid = place ? Math.min(owed, placeSpare(data, place, at)) : 0;
  if (place) await takeFromPlace(client, world, place, paid, at);
  const settled = settleSupply(data, fed, at, world.speed);
  return { ...settled, quarteredAt: place && paid >= owed - 1e-9 ? at : null };
}

// An army standing at a place with grain to spare is quartered there: the
// place feeds it from now and its own grain keeps (not saved).
export async function quarter(client: DbClient, data: GameData, world: World, army: Army, at: Date): Promise<Army> {
  const fed = supplied(army);
  if (!fed || army.quarteredAt) return army;
  const place = await placeOf(client, army);
  if (!place || placeSpare(data, place, at) <= 0) return army;
  return { ...settleSupply(data, fed, at, world.speed), quarteredAt: at, hungrySince: null };
}

// An army leaving where it stood: what it owes is paid and it eats its
// own grain from now (not saved).
async function unquarter(client: DbClient, data: GameData, world: World, army: Army, at: Date): Promise<Army> {
  if (!army.quarteredAt) return army;
  const settled = await settleQuarters(client, data, world, army, at);
  return { ...settled, quarteredAt: null };
}

function grainOnly(grain: number): Resources {
  return mapResources((kind) => (kind === 'grain' ? grain : 0));
}

function supplied(army: Army): (Army & Supplied) | null {
  return army.supply === null || army.supplyAt === null ? null : (army as Army & Supplied);
}

// An army setting off pays its quarters, then fills up to its full supply
// from where it stood (down to the place's floor), or leaves behind the
// grain it carries beyond its full supply; either way hunger comes at
// another time, so it is planned again. One sent off from a battle fills
// nothing (the battle keeps the stores).
async function setOff(client: DbClient, data: GameData, world: World, army: Army, at: Date): Promise<Army> {
  if (!supplied(army)) return army;
  let next = await unquarter(client, data, world, army, at);
  // Where it stood, as its stores are now that its quarters are paid.
  const place = army.status === 'stationed' ? await placeOf(client, army) : null;
  if (place) next = await fillUp(client, data, world, next, place, at);
  next = trimSupply(data, supplied(next)!, at, world.speed);
  return planHunger(client, data, world, next, at);
}

// Saves when the army's food next needs looking at and schedules it: for a
// quartered army, its place is charged every game hour; one standing at a
// place that can't feed it now tries again every game hour (and goes
// hungry as any other once its own grain is gone); nothing while it eats
// nothing, or carries no supply.
export async function planHunger(client: DbClient, data: GameData, world: World, army: Army, at: Date): Promise<Army> {
  const fed = supplied(army);
  let next: Date | null = null;
  if (fed) {
    const tick = new Date(at.getTime() + quarterTickMs(world.speed));
    if (army.quarteredAt) next = tick;
    else {
      next = nextHungerCheck(data, fed, at, world.speed);
      if ((army.status === 'stationed' || army.status === 'engaged') && (await placeOf(client, army)) && (!next || next > tick)) next = tick;
    }
  }
  const planned: Army = { ...army, hungerAt: next };
  await saveArmy(client, planned);
  if (next) await scheduleEvent(client, world.id, next, 'army_hunger', { armyId: army.id } satisfies ArmyPayload);
  return planned;
}

// An army ends in a village of its owner: the troops join the garrison,
// what grain and loot it carries go into the stores, and whoever led it
// stays there.
async function joinVillage(client: DbClient, data: GameData, world: World, army: Army, villageId: number, at: Date): Promise<void> {
  // Quartered where it stood (perhaps this very village): that is paid first.
  army = await unquarter(client, data, world, army, at);
  const village = await loadVillage(client, villageId);
  const fed = supplied(army);
  let state = completeTraining(village.state, at);
  if (fed) {
    state = joinGarrison(data, state, army.units, at, world.speed);
    // Its grain and loot into the stores.
    const load = mapResources((kind) => (army.loot?.[kind] ?? 0) + (kind === 'grain' ? supplyLeft(data, fed, at, world.speed) : 0));
    state = { ...state, ledger: receive(state.ledger, at, load).ledger };
    await saveVillageState(client, village.id, state);
    await saveArmy(client, { ...army, status: 'done', loot: null, supply: 0, supplyAt: at, hungerAt: null });
  } else {
    // An army from before supplies, coming home: its village fed it.
    for (const [unit, n] of Object.entries(army.units)) state = returnHome(data, state, unit, n, at, world.speed);
    await saveVillageState(client, village.id, state);
    await saveArmy(client, { ...army, status: 'done' });
    await deliverLoot(client, world, { ...army, status: 'done' }, at);
  }
  const hero = await heroWithArmy(client, army.id);
  if (hero) {
    await saveHero(client, { ...hero, status: 'home', villageId: village.id, armyId: null });
    await notifyWorld(client, { worldId: world.id, type: 'heroes' });
  }
  const general = await generalWithArmy(client, army.id);
  if (general) {
    await saveGeneral(client, { ...general, status: 'home', villageId: village.id, armyId: null });
    await notifyWorld(client, { worldId: world.id, type: 'generals' });
  }
  await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
}

// An army lost for good (starved): the hero is carried home wounded and
// the general is dead.
export async function endArmy(client: DbClient, data: GameData, world: World, army: Army, at: Date): Promise<Army> {
  const gone: Army = { ...army, units: {}, status: 'done', battleId: null, leavesAt: at, returnsAt: at, hungerAt: null };
  return sendHome(client, world, gone, at, data);
}

// Turns an army for home, along the road it came. An army with no one left
// is done; its hero is carried home wounded, and its general is dead.
export async function sendHome(client: DbClient, world: World, army: Army, at: Date, data?: GameData): Promise<Army> {
  if (total(army.units) === 0) {
    const gone: Army = { ...army, status: 'done', battleId: null, leavesAt: at, returnsAt: at };
    await saveArmy(client, gone);
    const hero = await heroWithArmy(client, army.id);
    if (hero && data) {
      const woundedUntil = new Date(at.getTime() + woundMs(data, world.speed, hero.kind, await hallLevelAt(client, army.homeVillageId)));
      await saveHero(client, { ...hero, status: 'wounded', villageId: army.homeVillageId, armyId: null, woundedUntil });
      await scheduleEvent(client, world.id, woundedUntil, 'hero_recover', { accountId: hero.accountId });
      await notifyWorld(client, { worldId: world.id, type: 'heroes' });
    }
    const general = await generalWithArmy(client, army.id);
    if (general) await killGeneral(client, world, general, at);
    return gone;
  }
  if (data) army = await setOff(client, data, world, army, at);
  // An army that moved on from where it first went takes the road home
  // from where it stands (drawn backwards, as every road home is).
  let path = army.path;
  const home = await loadVillage(client, army.homeVillageId).catch(() => null);
  if (home && data && (path[0]!.q !== home.q || path[0]!.r !== home.r)) {
    const fed = supplied(army);
    const speed = armySpeed(data, army.units) * supplySpeedFactor(data, fed, at, world.speed);
    path = roadRoute(data, await terrainOf(client, world.id), hex(home.q, home.r), hex(army.targetQ, army.targetR), speed, world.speed, terrainRelief(data, army.units));
  }
  const back: Army = {
    ...army,
    path,
    status: 'returning',
    battleId: null,
    wagonFortAt: null,
    leavesAt: at,
    returnsAt: new Date(at.getTime() + path.at(-1)!.atMs),
  };
  await saveArmy(client, back);
  const payload: ArmyPayload = { armyId: army.id };
  await scheduleEvent(client, world.id, back.returnsAt!, 'army_return', payload);
  return back;
}

// An army joins the battle at its target village from the next round.
async function joinBattle(client: DbClient, data: GameData, world: World, army: Army, battle: Battle, wave: Wave, at: Date): Promise<Army> {
  const villageHex = hex(battle.q, battle.r);
  const hordeStep = wave.path?.filter((s) => s.q !== battle.q || s.r !== battle.r).at(-1);
  const armyStep = army.path.at(-2);
  const angle = hordeStep && armyStep ? approachAngle(villageHex, hex(hordeStep.q, hordeStep.r), hex(armyStep.q, armyStep.r)) : 0;
  const bonus = joinBonus(data, { orders: army.orders, armySize: total(army.units), hordeSize: total(wave.composition), angle });
  const joined: Army = { ...army, status: 'engaged', battleId: battle.id, joinsRound: battle.round + 1, joinBonus: bonus, engagedUnits: army.units };
  await planHunger(client, data, world, joined, at);
  await addDefenders(client, battle.id, combatants(data, army.units));
  return joined;
}

// A battle starts at a village: armies standing there join at once, and
// armies standing nearby answer it.
export async function rallyToBattle(
  client: DbClient,
  data: GameData,
  world: World,
  battle: Battle,
  village: Village,
  at: Date,
): Promise<void> {
  for (const army of await armiesAt(client, village.id, ['stationed'])) {
    await saveArmy(client, { ...army, status: 'engaged', battleId: battle.id, joinsRound: 1, joinBonus: 0, engagedUnits: army.units });
    await addDefenders(client, battle.id, combatants(data, army.units));
  }
  await answerBattle(client, data, world, hex(village.q, village.r), village.id, at);
  await notifyWorld(client, { worldId: world.id, type: 'armies' });
}

// Standing armies that answer a battle at `cell`: every army standing
// within respond.range hexes of it (not there already) that fights and
// was not told to stay out.
export async function respondersTo(client: DbClient, data: GameData, worldId: number, cell: Hex): Promise<Army[]> {
  return (await listArmies(client, worldId, 0)).filter(
    (a) =>
      a.status === 'stationed' &&
      a.respond &&
      a.orders !== 'explore' &&
      (a.targetQ !== cell.q || a.targetR !== cell.r) &&
      hexDistance(hex(a.targetQ, a.targetR), cell) <= data.armies.respond.range &&
      total(combatants(data, a.units)) > 0,
  );
}

// Armies standing nearby march to a battle that started at `cell` (a
// village's, or on open ground), remembering where they stood: they go
// back once it is over.
export async function answerBattle(client: DbClient, data: GameData, world: World, cell: Hex, villageId: number | null, at: Date): Promise<void> {
  for (const army of await respondersTo(client, data, world.id, cell)) {
    const post: ArmyPost = { q: army.targetQ, r: army.targetR, villageId: army.targetVillageId };
    await client.query('SAVEPOINT respond');
    try {
      const to = villageId !== null ? { villageId, orders: 'reinforce' as const } : { hex: cell, orders: 'hold' as const };
      const moving = await moveArmy(client, data, world, army, to, at);
      await saveArmy(client, { ...moving, post });
      await client.query('RELEASE SAVEPOINT respond');
    } catch (error) {
      // No road there: it can't help.
      await client.query('ROLLBACK TO SAVEPOINT respond');
      if (!(error instanceof RuleError)) throw error;
    }
  }
}

// The ongoing battle with a horde on open ground at a hex, if any.
export async function fieldBattleAt(client: DbClient, worldId: number, cell: Hex): Promise<Battle | null> {
  const { rows } = await client.query<{ id: number }>(
    `SELECT id FROM battles WHERE world_id = $1 AND q = $2 AND r = $3 AND village_id IS NULL AND wave_id IS NOT NULL AND status = 'ongoing' ORDER BY id LIMIT 1`,
    [worldId, cell.q, cell.r],
  );
  return rows[0] ? loadBattle(client, rows[0].id) : null;
}

// An army done with a battle it went to: one that answered it goes back to
// where it stood; any other goes home.
export async function afterBattle(client: DbClient, data: GameData, world: World, army: Army, at: Date): Promise<Army> {
  if (!army.post || total(army.units) === 0) return sendHome(client, world, army, at, data);
  const post = army.post;
  const done: Army = { ...army, status: 'stationed', battleId: null, joinsRound: null, joinBonus: 0, post: null };
  if (done.targetQ === post.q && done.targetR === post.r) return planHunger(client, data, world, await quarter(client, data, world, done, at), at);
  await client.query('SAVEPOINT back');
  try {
    const to = post.villageId !== null ? { villageId: post.villageId, join: false } : { hex: hex(post.q, post.r), orders: 'hold' as const };
    const back = await moveArmy(client, data, world, done, to, at);
    await client.query('RELEASE SAVEPOINT back');
    return back;
  } catch (error) {
    // Where it stood is gone (or out of reach): it goes home.
    await client.query('ROLLBACK TO SAVEPOINT back');
    if (!(error instanceof RuleError)) throw error;
    return sendHome(client, world, done, at, data);
  }
}

// Losses an army took: its supply is settled first (the dead stop eating),
// or, for an army from before supplies, its home village stops feeding them.
export async function armyLosses(
  client: DbClient,
  data: GameData,
  world: World,
  army: Army,
  fallen: Record<string, number>,
  at: Date,
  wounds = true,
): Promise<Army> {
  if (total(fallen) === 0) return army;
  // Shamans with the army put some of those who fell in battle back on
  // their feet (not the starving).
  const chance = wounds ? healerChance(data, army.units) : 0;
  const healed = healFallen(chance, fallen, createRng((world.seed ^ Math.imul(army.id + 1, 0x632be5ab) ^ (Math.floor(at.getTime() / 60_000) & 0xfffff)) >>> 0));
  const losses: Record<string, number> = {};
  for (const [unit, n] of Object.entries(fallen)) if (n - (healed[unit] ?? 0) > 0) losses[unit] = n - (healed[unit] ?? 0);
  if (total(losses) === 0) return army;
  // Quartered, its place is paid for what the fallen ate till now.
  army = await settleQuarters(client, data, world, army, at);
  const fed = supplied(army);
  let before: Army = army;
  if (fed) {
    before = settleSupply(data, fed, at, world.speed);
  } else {
    const home = await loadVillage(client, army.homeVillageId);
    let state = home.state;
    for (const [unit, n] of Object.entries(losses)) state = loseAway(data, state, unit, n, at, world.speed);
    await saveVillageState(client, home.id, state);
    await notifyWorld(client, { worldId: world.id, type: 'village', villageId: home.id });
  }
  const units: Record<string, number> = {};
  for (const [unit, n] of Object.entries(army.units)) if (n - (losses[unit] ?? 0) > 0) units[unit] = n - (losses[unit] ?? 0);
  return { ...before, units };
}

export const armyHandlers: HandlerRegistry = {
  async army_arrive({ client, data, world }, event) {
    const army = await loadArmy(client, armyPayload.parse(event.payload).armyId);
    // Turned on the road since: a later arrival is planned.
    if (army.status !== 'marching' || army.arrivesAt.getTime() !== event.dueAt.getTime()) return;
    if (army.orders === 'explore') {
      await arriveAtSite(client, data, world, army, event.dueAt);
      await notifyWorld(client, { worldId: world.id, type: 'armies' });
      return;
    }
    if (army.orders === 'raid') {
      await reachEdge(client, data, world, army, event.dueAt);
      await notifyWorld(client, { worldId: world.id, type: 'armies' });
      return;
    }
    if (army.orders === 'clear') {
      await stormCamp(client, data, world, army, event.dueAt);
      await notifyWorld(client, { worldId: world.id, type: 'armies' });
      return;
    }
    if (army.orders === 'hold') {
      // Told to come home once there (and not guarding a shipyard), it turns back.
      if (!(await staysOut(client, world, army))) {
        await sendHome(client, world, army, event.dueAt, data);
        await notifyWorld(client, { worldId: world.id, type: 'armies' });
        return;
      }
      const fort = await fortAt(client, world.id, army.targetQ, army.targetR);
      if (fort) await markFortManned(client, fort.id, event.dueAt);
      // On a fort or supply point it is quartered there.
      const stationed = await quarter(client, data, world, { ...army, status: 'stationed' }, event.dueAt);
      // A battle on the hex: it joins it from the next round.
      const battle = await fieldBattleAt(client, world.id, hex(army.targetQ, army.targetR));
      if (battle?.waveId) await joinBattle(client, data, world, stationed, battle, await loadWave(client, battle.waveId), event.dueAt);
      else await planHunger(client, data, world, stationed, event.dueAt);
      await interceptAt(client, data, world, hex(army.targetQ, army.targetR), event.dueAt);
      await notifyWorld(client, { worldId: world.id, type: 'armies' });
      return;
    }
    const { rows } = await client.query<{ id: number }>(
      `SELECT id FROM battles WHERE village_id = $1 AND status = 'ongoing' LIMIT 1`,
      [army.targetVillageId],
    );
    if (army.orders === 'garrison') {
      await joinVillage(client, data, world, army, army.targetVillageId!, event.dueAt);
      await notifyWorld(client, { worldId: world.id, type: 'armies' });
      return;
    }
    // Any village it reaches quarters it.
    const arrived = await quarter(client, data, world, { ...army, status: 'stationed' }, event.dueAt);
    const ongoing = rows[0] ? await loadBattle(client, rows[0].id) : null;
    if (ongoing?.waveId) {
      await joinBattle(client, data, world, arrived, ongoing, await loadWave(client, ongoing.waveId), event.dueAt);
    } else if (army.orders === 'support' && !army.returnHome) {
      await planHunger(client, data, world, arrived, event.dueAt);
    } else {
      await afterBattle(client, data, world, arrived, event.dueAt);
    }
    await notifyWorld(client, { worldId: world.id, type: 'armies' });
  },

  async army_return({ client, data, world }, event) {
    const army = await loadArmy(client, armyPayload.parse(event.payload).armyId);
    if (army.status !== 'returning' || army.returnsAt?.getTime() !== event.dueAt.getTime()) return;
    // The troops join the garrison; loot from a cleared camp and what grain
    // is left go into the stores.
    await joinVillage(client, data, world, army, army.homeVillageId, event.dueAt);
    await notifyWorld(client, { worldId: world.id, type: 'armies' });
  },

  // Out of food: the army loses men, or is lost altogether.
  async army_hunger({ client, data, world }, event) {
    const army = await loadArmy(client, armyPayload.parse(event.payload).armyId).catch(() => null);
    const fed = army && supplied(army);
    if (!army || !fed || army.status === 'done' || !army.hungerAt || army.hungerAt.getTime() !== event.dueAt.getTime()) return;
    // Quartered, its place pays for the hour (or can't, and it eats its
    // own from now); standing at a place with grain again, it is quartered.
    const current = army.quarteredAt ? await settleQuarters(client, data, world, army, event.dueAt) : await quarter(client, data, world, army, event.dueAt);
    if (current.quarteredAt) {
      await planHunger(client, data, world, current, event.dueAt);
      return;
    }
    const strike = hungerStrikes(data, supplied(current)!, event.dueAt, world.speed);
    const name = (await loadVillage(client, army.homeVillageId).catch(() => null))?.name ?? '';
    const thinned = strike.lost ? current : await armyLosses(client, data, world, current, strike.losses, event.dueAt, false);
    if (strike.lost || total(thinned.units) === 0) {
      await endArmy(client, data, world, thinned, event.dueAt);
      await tell(client, world, army.ownerAccountId, {
        kind: 'battle_result',
        tier: 'push',
        title: 'An army from {village} starved',
        body: 'With no food left it scattered; none of them will come back.',
        vars: { village: name },
      }, event.dueAt);
    } else {
      await planHunger(client, data, world, thinned, event.dueAt);
    }
    await notifyWorld(client, { worldId: world.id, type: 'armies' });
  },
};

// Newly trained troops march to their owner's rally point (another of their
// own settlements), if one is set: each batch done (`batches`, as they stood
// before settling) sends as many of its unit as stand at home, up to its
// size, as one army joining the garrison there. Troops that can't march
// (settlers), or a village under siege, stay home.
export async function rallyTrained(client: DbClient, data: GameData, world: World, villageId: number, batches: readonly TrainingBatch[], at: Date): Promise<void> {
  const home = await loadVillage(client, villageId);
  if (home.ownerAccountId === null || home.state.besieged || batches.length === 0) return;
  const rally = await rallyPoint(client, world.id, home.ownerAccountId);
  if (rally === null || rally === home.id) return;
  const target = await loadVillage(client, rally).catch(() => null);
  if (!target || target.worldId !== world.id || target.ownerAccountId !== home.ownerAccountId || target.ruin) return;
  const units: Record<string, number> = {};
  for (const batch of batches) {
    const def = data.units.units[batch.unit];
    const marches = def?.family === 'scout' || total(fighters(data, { [batch.unit]: 1 })) > 0;
    if (!marches) continue;
    const left = (home.state.garrison[batch.unit] ?? 0) - (units[batch.unit] ?? 0);
    const n = Math.min(left, batch.size ?? batch.count);
    if (n > 0) units[batch.unit] = (units[batch.unit] ?? 0) + n;
  }
  if (total(fighters(data, units)) === 0) return;
  await client.query('SAVEPOINT rally');
  try {
    await dispatchArmy(client, data, world, { homeVillageId: home.id, targetVillageId: target.id, units, orders: 'garrison', at });
    await client.query('RELEASE SAVEPOINT rally');
  } catch (error) {
    await client.query('ROLLBACK TO SAVEPOINT rally');
    if (!(error instanceof RuleError)) throw error;
  }
}

// A leader leaving an army out in the field makes their own way to a
// village: a hero walks, a general rides.
async function heroTo(client: DbClient, data: GameData, world: World, hero: Hero, from: Hex, village: Village, at: Date): Promise<void> {
  const land = await terrainOf(client, world.id);
  const path = roadRoute(data, land, from, hex(village.q, village.r), data.heroes.speed * heroFactor(data, hero.kind, 'heroSpeed'), world.speed);
  const arrivesAt = new Date(at.getTime() + path.at(-1)!.atMs);
  await saveHero(client, { ...hero, status: 'traveling', villageId: village.id, armyId: null, path, departsAt: at, arrivesAt });
  await scheduleEvent(client, world.id, arrivesAt, 'hero_arrive', { accountId: hero.accountId });
  await notifyWorld(client, { worldId: world.id, type: 'heroes' });
}

async function generalTo(client: DbClient, data: GameData, world: World, general: General, from: Hex, village: Village, at: Date): Promise<void> {
  const land = await terrainOf(client, world.id);
  const path = roadRoute(data, land, from, hex(village.q, village.r), data.heroes.generals.speed, world.speed);
  const until = new Date(at.getTime() + path.at(-1)!.atMs);
  await saveGeneral(client, { ...general, status: 'traveling', villageId: village.id, armyId: null, path, departsAt: at, until });
  await scheduleEvent(client, world.id, until, 'general_arrive', { generalId: general.id });
  await notifyWorld(client, { worldId: world.id, type: 'generals' });
}

// The village of its owner's an army stands in (null: none).
async function ownVillageHere(client: DbClient, army: Army): Promise<Village | null> {
  if (army.targetVillageId === null || (army.status !== 'stationed' && army.status !== 'engaged')) return null;
  const village = await loadVillage(client, army.targetVillageId).catch(() => null);
  return village && village.ownerAccountId === army.ownerAccountId && !village.ruin ? village : null;
}

function notInBattle(army: Army): void {
  if (army.status === 'engaged') throw new RuleError('That army is in the middle of a battle');
  if (army.status === 'done') throw new RuleError('That army is no more');
}

// An army's home: another settlement of its owner's (where it goes when
// called home).
export async function setArmyHome(client: DbClient, world: World, army: Army, villageId: number): Promise<Army> {
  if (army.status === 'done') throw new RuleError('That army is no more');
  if (army.status === 'returning') throw new RuleError('They are on their way home; turn them first');
  const village = await loadVillage(client, villageId).catch(() => null);
  if (!village || village.worldId !== world.id || village.ownerAccountId !== army.ownerAccountId || village.ruin) {
    throw new RuleError('Only one of your own settlements can be its home');
  }
  if (village.id === army.homeVillageId) throw new RuleError(`${village.name} is its home already`);
  const next: Army = { ...army, homeVillageId: village.id };
  await saveArmy(client, next);
  return next;
}

// Whether a standing army answers battles nearby.
export async function setRespond(client: DbClient, army: Army, respond: boolean): Promise<Army> {
  if (army.status === 'done') throw new RuleError('That army is no more');
  const next: Army = { ...army, respond };
  await saveArmy(client, next);
  return next;
}

// The owner's hero joins a standing army in the village where the hero is,
// or leaves it (not in a battle): into the village it stands in if it is
// the owner's, else on the road to the army's home.
export async function armyHero(client: DbClient, data: GameData, world: World, army: Army, join: boolean, at: Date): Promise<Army> {
  notInBattle(army);
  const led = await heroWithArmy(client, army.id);
  if (join) {
    if (led) throw new RuleError(`${led.name} leads them already`);
    if (army.status !== 'stationed') throw new RuleError('Only a standing army can take on a hero');
    const hero = await loadHero(client, world.id, army.ownerAccountId!).catch(() => null);
    if (!hero) throw new RuleError('You have no hero');
    if (hero.status !== 'home' || army.targetVillageId === null || hero.villageId !== army.targetVillageId) throw new RuleError(`${hero.name} is not where they stand`);
    await saveHero(client, { ...hero, status: 'with_army', villageId: null, armyId: army.id });
    await setArmyLeaders(client, army.id, hero.accountId, (await generalWithArmy(client, army.id))?.id ?? null);
    await notifyWorld(client, { worldId: world.id, type: 'heroes' });
    return { ...army, heroAccountId: hero.accountId };
  }
  if (!led) throw new RuleError('No hero leads them');
  const village = await ownVillageHere(client, army);
  if (village) {
    await saveHero(client, { ...led, status: 'home', villageId: village.id, armyId: null });
    await notifyWorld(client, { worldId: world.id, type: 'heroes' });
  } else {
    await heroTo(client, data, world, led, armyHex(army, at), await loadVillage(client, army.homeVillageId), at);
  }
  await setArmyLeaders(client, army.id, null, (await generalWithArmy(client, army.id))?.id ?? null);
  return { ...army, heroAccountId: null };
}

// Where an army is now: the hex it stands on, or for one on the road the
// last hex it reached.
function armyHex(army: Army, at: Date): Hex {
  if (army.status === 'stationed' || army.status === 'engaged') return hex(army.targetQ, army.targetR);
  const road = army.status === 'returning' ? reversedRoute(army.path) : army.path;
  const since = at.getTime() - (army.status === 'returning' ? army.leavesAt! : army.departsAt).getTime();
  const step = [...road].reverse().find((s) => s.atMs <= since) ?? road[0]!;
  return hex(step.q, step.r);
}

// A general takes command of a standing army in the village where the
// general is (the one leading it stays there), or the general leading it
// leaves (generalId null), as a hero would. Not in a battle.
export async function armyGeneral(client: DbClient, data: GameData, world: World, army: Army, generalId: number | null, at: Date): Promise<Army> {
  notInBattle(army);
  const current = await generalWithArmy(client, army.id);
  const heroId = (await heroWithArmy(client, army.id))?.accountId ?? null;
  if (generalId === null) {
    if (!current) throw new RuleError('No general leads them');
    const village = await ownVillageHere(client, army);
    if (village) {
      await saveGeneral(client, { ...current, status: 'home', villageId: village.id, armyId: null });
      await notifyWorld(client, { worldId: world.id, type: 'generals' });
    } else {
      await generalTo(client, data, world, current, armyHex(army, at), await loadVillage(client, army.homeVillageId), at);
    }
    await setArmyLeaders(client, army.id, heroId, null);
    return { ...army, generalId: null };
  }
  if (army.status !== 'stationed') throw new RuleError('Only a standing army can take on a general');
  const general = await loadGeneral(client, generalId).catch(() => null);
  if (!general || general.accountId !== army.ownerAccountId) throw new RuleError('No such general');
  if (general.id === current?.id) throw new RuleError(`${general.name} leads them already`);
  if (general.status !== 'home' || army.targetVillageId === null || general.villageId !== army.targetVillageId) throw new RuleError(`${general.name} is not where they stand`);
  if (current) await saveGeneral(client, { ...current, status: 'home', villageId: army.targetVillageId, armyId: null });
  await saveGeneral(client, { ...general, status: 'with_army', villageId: null, armyId: army.id });
  await setArmyLeaders(client, army.id, heroId, general.id);
  await notifyWorld(client, { worldId: world.id, type: 'generals' });
  return { ...army, generalId: general.id };
}

// Two standing armies of one owner on the same place become one: the
// other's troops, grain, loot and leaders join this one (at most one
// general between them).
export async function mergeArmies(client: DbClient, data: GameData, world: World, army: Army, otherId: number, at: Date): Promise<Army> {
  standing(army);
  if (otherId === army.id) throw new RuleError('Pick another army');
  const other = await loadArmy(client, otherId).catch(() => null);
  if (!other || other.worldId !== world.id || other.ownerAccountId !== army.ownerAccountId) throw new RuleError('No such army of yours');
  standing(other);
  if (other.targetQ !== army.targetQ || other.targetR !== army.targetR) throw new RuleError('They must stand on the same hex');
  const [heroA, heroB] = [await heroWithArmy(client, army.id), await heroWithArmy(client, other.id)];
  const [genA, genB] = [await generalWithArmy(client, army.id), await generalWithArmy(client, other.id)];
  if (genA && genB) throw new RuleError('Both have a general: send one away first');
  // Both pay their quarters and eat their own for a moment.
  const a = await unquarter(client, data, world, army, at);
  const b = await unquarter(client, data, world, other, at);
  const fedA = supplied(a);
  const fedB = supplied(b);
  const supply = fedA || fedB ? (fedA ? supplyLeft(data, fedA, at, world.speed) : 0) + (fedB ? supplyLeft(data, fedB, at, world.speed) : 0) : null;
  const loot = a.loot || b.loot ? mapResources((kind) => (a.loot?.[kind] ?? 0) + (b.loot?.[kind] ?? 0)) : null;
  await saveArmy(client, { ...b, units: {}, status: 'done', supply: 0, supplyAt: at, hungerAt: null, loot: null, leavesAt: at, returnsAt: at });
  const hero = heroA ?? heroB;
  const general = genA ?? genB;
  if (heroB) await saveHero(client, { ...heroB, armyId: army.id });
  if (genB) await saveGeneral(client, { ...genB, armyId: army.id });
  await setArmyLeaders(client, army.id, hero?.accountId ?? null, general?.id ?? null);
  await setArmyLeaders(client, other.id, null, null);
  if (heroB) await notifyWorld(client, { worldId: world.id, type: 'heroes' });
  if (genB) await notifyWorld(client, { worldId: world.id, type: 'generals' });
  const merged: Army = {
    ...a,
    units: addUnits(a.units, b.units),
    supply,
    supplyAt: supply === null ? null : at,
    hungrySince: null,
    loot,
    heroAccountId: hero?.accountId ?? null,
    generalId: general?.id ?? null,
    // A ring of wagons is drawn anew.
    wagonFortAt: a.wagonFortAt && b.wagonFortAt ? new Date(Math.max(a.wagonFortAt.getTime(), b.wagonFortAt.getTime())) : a.wagonFortAt,
  };
  return planHunger(client, data, world, await quarter(client, data, world, merged, at), at);
}

// A standing army splits off some of its troops as an army of their own on
// the same place, with their share of its grain, and its hero or general
// if told so (its loot stays).
export async function splitArmy(
  client: DbClient,
  data: GameData,
  world: World,
  army: Army,
  spec: { units: Record<string, number>; withHero?: boolean | undefined; withGeneral?: boolean | undefined },
  at: Date,
): Promise<{ army: Army; split: Army }> {
  standing(army);
  const units: Record<string, number> = {};
  for (const [unit, n] of Object.entries(spec.units)) {
    if (!Number.isInteger(n) || n < 0) throw new RuleError('Pick whole troops');
    if (n > (army.units[unit] ?? 0)) throw new RuleError('They have not so many');
    if (n > 0) units[unit] = n;
  }
  const rest: Record<string, number> = {};
  for (const [unit, n] of Object.entries(army.units)) if (n - (units[unit] ?? 0) > 0) rest[unit] = n - (units[unit] ?? 0);
  if (total(units) === 0) throw new RuleError('Pick who goes');
  if (total(rest) === 0) throw new RuleError('Leave someone behind');
  const hero = spec.withHero ? await heroWithArmy(client, army.id) : null;
  if (spec.withHero && !hero) throw new RuleError('No hero leads them');
  const general = spec.withGeneral ? await generalWithArmy(client, army.id) : null;
  if (spec.withGeneral && !general) throw new RuleError('No general leads them');
  const settled = await unquarter(client, data, world, army, at);
  const fed = supplied(settled);
  const carried = fed ? supplyLeft(data, fed, at, world.speed) : 0;
  const whole = fullSupply(data, army.units);
  const share = whole > 0 ? fullSupply(data, units) / whole : total(units) / total(army.units);
  const taken = fed ? carried * share : null;
  const created = await insertArmy(client, {
    worldId: world.id,
    ownerAccountId: army.ownerAccountId,
    homeVillageId: army.homeVillageId,
    targetVillageId: army.targetVillageId,
    targetQ: army.targetQ,
    targetR: army.targetR,
    heroAccountId: hero?.accountId ?? null,
    generalId: general?.id ?? null,
    orders: army.orders === 'support' || army.orders === 'hold' ? army.orders : army.targetVillageId === null ? 'hold' : 'support',
    stance: army.stance,
    returnHome: army.returnHome,
    respond: army.respond,
    units,
    supply: taken,
    supplyAt: fed ? at : null,
    path: [{ q: army.targetQ, r: army.targetR, atMs: 0 }],
    departsAt: at,
    arrivesAt: at,
  });
  if (hero) {
    await saveHero(client, { ...hero, armyId: created.id });
    await notifyWorld(client, { worldId: world.id, type: 'heroes' });
  }
  if (general) {
    await saveGeneral(client, { ...general, armyId: created.id });
    await notifyWorld(client, { worldId: world.id, type: 'generals' });
  }
  const leftHero = hero ? null : ((await heroWithArmy(client, army.id))?.accountId ?? null);
  const leftGeneral = general ? null : ((await generalWithArmy(client, army.id))?.id ?? null);
  await setArmyLeaders(client, army.id, leftHero, leftGeneral);
  const kept: Army = {
    ...settled,
    units: rest,
    supply: fed ? carried - taken! : settled.supply,
    supplyAt: fed ? at : settled.supplyAt,
    heroAccountId: leftHero,
    generalId: leftGeneral,
  };
  const left = await planHunger(client, data, world, await quarter(client, data, world, kept, at), at);
  const split = await planHunger(client, data, world, await quarter(client, data, world, { ...created, status: 'stationed', wagonFortAt: null }, at), at);
  return { army: left, split };
}
