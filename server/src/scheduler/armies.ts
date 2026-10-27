// Armies on the scheduler: army_arrive (station, join a battle, hold a hex,
// join a garrison, or turn back), army_return (home again), army_hunger
// (an army out of food losing men, or lost). Battles (battles.ts, field.ts)
// use the helpers here to fold armies into the defenders and to call in
// reinforcements. Armies carry their own grain (sim/supply.ts); armies from
// before that (supply null) are fed by their home village.
import { loadLand } from '../db/rivers.js';
import type { Land } from '../sim/land.js';
import { z } from 'zod';
import type { GameData, TerrainId } from '../data/index.js';
import { armiesAt, insertArmy, loadArmy, loadReinforceRule, saveArmy, type Army } from '../db/armies.js';
import { addDefenders, loadBattle, type Battle } from '../db/battles.js';
import { heroWithArmy, loadHero, saveHero } from '../db/heroes.js';
import { generalWithArmy, loadGeneral, saveGeneral } from '../db/generals.js';
import { hallLevelAt, killGeneral } from './generals.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { listVillages, loadVillage, saveVillageState, type Village } from '../db/villages.js';
import { heroFactor } from '../sim/heroes.js';
import { loadWave, type Wave } from '../db/waves.js';
import { loadHexes, type World } from '../db/worlds.js';
import { RuleError } from '../errors.js';
import { approachAngle, armySpeed, joinBonus, shareOf, total, validateArmy, type ArmyOrders } from '../sim/armies.js';
import { hex, hexDistance, type Hex } from '../sim/hex.js';
import { woundMs } from '../sim/heroes.js';
import { roadRoute } from '../sim/logistics.js';
import { completeTraining, joinGarrison, leaveGarrison, loseAway, returnHome } from '../sim/village.js';
import { addSupply, fullSupply, hungerStrikes, nextHungerCheck, outOfFoodAt, settleSupply, supplyLeft, supplyRoom, supplySpeedFactor, type Supplied } from '../sim/supply.js';
import { amountsAt, mapResources, spend, type Resources } from '../sim/resources.js';
import { receive } from '../sim/logistics.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';
import { tell } from './notices.js';
import { interceptAt } from './field.js';
import { deliverLoot, stormCamp } from './camps.js';
import { arriveAtSite } from './sites.js';
import { siteAt } from '../db/sites.js';
import { campAt } from '../db/camps.js';
import { fortAt, markFortManned } from '../db/forts.js';

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
    to = hex(target.q, target.r);
  }
  // The troops leave the garrison with what grain the village can spare.
  let state = leaveGarrison(data, home.state, units, input.at, world.speed);
  const grain = Math.min(fullSupply(data, units), amountsAt(state.ledger, input.at).grain);
  state = { ...state, ledger: spend(state.ledger, input.at, grainOnly(grain)) };
  const supplied: Supplied = { units, supply: grain, supplyAt: input.at, hungrySince: null };
  const speed = armySpeed(data, units) * supplySpeedFactor(data, supplied, input.at, world.speed);
  const path = roadRoute(data, await terrainOf(client, world.id), hex(home.q, home.r), to, speed, world.speed);

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
    targetVillageId: ['hold', 'clear', 'explore'].includes(input.orders) ? null : input.targetVillageId,
    supply: grain,
    supplyAt: input.at,
    targetQ: to.q,
    targetR: to.r,
    heroAccountId,
    generalId,
    orders: input.orders,
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
  const holding: Army = { ...army, status: 'stationed', orders: 'hold', targetVillageId: null, battleId: null };
  await saveArmy(client, holding);
  await interceptAt(client, data, world, hex(army.targetQ, army.targetR), at);
  return holding;
}

// Where a standing army goes next: a hex to hold, or a village (its owner's
// to join the garrison, another to support).
export async function moveArmy(
  client: DbClient,
  data: GameData,
  world: World,
  army: Army,
  to: { hex?: Hex | undefined; villageId?: number | undefined },
  at: Date,
): Promise<Army> {
  standing(army);
  const here = hex(army.targetQ, army.targetR);
  let dest: Hex;
  let orders: ArmyOrders = 'hold';
  let targetVillageId: number | null = null;
  if (to.villageId !== undefined) {
    const village = await loadVillage(client, to.villageId).catch(() => null);
    if (!village || village.worldId !== world.id) throw new RuleError('No such village in this world');
    dest = hex(village.q, village.r);
    orders = village.ownerAccountId === army.ownerAccountId ? 'garrison' : 'support';
    targetVillageId = village.id;
  } else {
    if (!to.hex) throw new RuleError('Say where they should go');
    dest = to.hex;
    const terrain = (await terrainOf(client, world.id)).get(`${dest.q},${dest.r}`);
    if (!terrain || data.terrain.terrain[terrain].moveCost === null) throw new RuleError('No army can stand there');
    if ((await listVillages(client, world.id)).some((v) => v.q === dest.q && v.r === dest.r)) throw new RuleError('That is a village; send them into it');
  }
  if (dest.q === here.q && dest.r === here.r) {
    // Already standing in its owner's village: it joins the garrison now.
    if (orders === 'garrison') {
      await joinVillage(client, data, world, army, targetVillageId!, at);
      return loadArmy(client, army.id);
    }
    throw new RuleError('They are already there');
  }
  const fed = supplied(army);
  const speed = armySpeed(data, army.units) * supplySpeedFactor(data, fed, at, world.speed);
  const path = roadRoute(data, await terrainOf(client, world.id), here, dest, speed, world.speed);
  const moving: Army = {
    ...army,
    orders,
    targetVillageId,
    targetQ: dest.q,
    targetR: dest.r,
    path,
    status: 'marching',
    battleId: null,
    departsAt: at,
    arrivesAt: new Date(at.getTime() + path.at(-1)!.atMs),
    leavesAt: null,
    returnsAt: null,
  };
  await saveArmy(client, moving);
  await scheduleEvent(client, world.id, moving.arrivesAt, 'army_arrive', { armyId: army.id } satisfies ArmyPayload);
  return moving;
}

function standing(army: Army): void {
  if (army.status === 'engaged') throw new RuleError('That army is in the middle of a battle');
  if (army.status !== 'stationed') throw new RuleError('Only armies standing still can be given new orders');
}

// A standing army disbanded: its troops go home to their farms, and
// whoever led it makes their own way home.
export async function disbandArmy(client: DbClient, data: GameData, world: World, army: Army, at: Date): Promise<Army> {
  standing(army);
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

// A standing army in a village takes on what grain it can from its stores.
export async function resupplyArmy(client: DbClient, data: GameData, world: World, army: Army, at: Date): Promise<Army> {
  standing(army);
  if (army.targetVillageId === null) throw new RuleError('They stand in no village');
  if (!supplied(army)) throw new RuleError('Their village feeds them');
  return resupply(client, data, world, army, army.targetVillageId, at);
}

function grainOnly(grain: number): Resources {
  return mapResources((kind) => (kind === 'grain' ? grain : 0));
}

function supplied(army: Army): (Army & Supplied) | null {
  return army.supply === null || army.supplyAt === null ? null : (army as Army & Supplied);
}

// Saves when hunger next comes for an army and schedules it (nothing while
// it is fed for good, or carries no supply). An army standing in a village
// is fed from its stores the moment its own grain runs out.
export async function planHunger(client: DbClient, data: GameData, world: World, army: Army, at: Date): Promise<Army> {
  const fed = supplied(army);
  const out = fed ? outOfFoodAt(data, fed, world.speed) : null;
  const inVillage = (army.status === 'stationed' || army.status === 'engaged') && army.targetVillageId !== null;
  const next = fed ? (inVillage && out && out > at ? out : nextHungerCheck(data, fed, at, world.speed)) : null;
  const planned: Army = { ...army, hungerAt: next };
  await saveArmy(client, planned);
  if (next) await scheduleEvent(client, world.id, next, 'army_hunger', { armyId: army.id } satisfies ArmyPayload);
  return planned;
}

// An army at a village takes on what grain it can carry from its stores.
export async function resupply(client: DbClient, data: GameData, world: World, army: Army, villageId: number, at: Date): Promise<Army> {
  const fed = supplied(army);
  if (!fed) return army;
  const village = await loadVillage(client, villageId);
  const grain = Math.min(supplyRoom(data, fed, at, world.speed), amountsAt(village.state.ledger, at).grain);
  const settled = addSupply(data, fed, grain, at, world.speed);
  if (grain > 0) {
    await saveVillageState(client, village.id, { ...village.state, ledger: spend(village.state.ledger, at, grainOnly(grain)) });
    await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
  }
  return planHunger(client, data, world, settled, at);
}

// An army ends in a village of its owner: the troops join the garrison,
// what grain and loot it carries go into the stores, and whoever led it
// stays there.
async function joinVillage(client: DbClient, data: GameData, world: World, army: Army, villageId: number, at: Date): Promise<void> {
  const village = await loadVillage(client, villageId);
  const fed = supplied(army);
  let state = completeTraining(village.state, at);
  if (fed) {
    state = joinGarrison(data, state, army.units, at, world.speed);
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
  // An army that moved on from where it first went takes the road home
  // from where it stands (drawn backwards, as every road home is).
  let path = army.path;
  const home = await loadVillage(client, army.homeVillageId).catch(() => null);
  if (home && data && (path[0]!.q !== home.q || path[0]!.r !== home.r)) {
    const fed = supplied(army);
    const speed = armySpeed(data, army.units) * supplySpeedFactor(data, fed, at, world.speed);
    path = roadRoute(data, await terrainOf(client, world.id), hex(home.q, home.r), hex(army.targetQ, army.targetR), speed, world.speed);
  }
  const back: Army = {
    ...army,
    path,
    status: 'returning',
    battleId: null,
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
  const joined: Army = { ...army, status: 'engaged', battleId: battle.id, joinsRound: battle.round + 1, joinBonus: bonus };
  await planHunger(client, data, world, joined, at);
  await addDefenders(client, battle.id, army.units);
  return joined;
}

// A battle starts at a village: armies standing there join at once, and
// villages in range send their share of troops.
export async function rallyToBattle(
  client: DbClient,
  data: GameData,
  world: World,
  battle: Battle,
  village: Village,
  at: Date,
): Promise<void> {
  for (const army of await armiesAt(client, village.id, ['stationed'])) {
    await saveArmy(client, { ...army, status: 'engaged', battleId: battle.id, joinsRound: 1, joinBonus: 0 });
    await addDefenders(client, battle.id, army.units);
  }
  for (const other of await listVillages(client, world.id)) {
    if (other.id === village.id || other.state.besieged) continue;
    const rule = await loadReinforceRule(client, other.id);
    if (rule.share <= 0 || hexDistance(hex(other.q, other.r), hex(village.q, village.r)) > rule.range) continue;
    const units = shareOf(data, completeTraining(other.state, at).garrison, rule.share);
    if (total(units) === 0) continue;
    try {
      await dispatchArmy(client, data, world, { homeVillageId: other.id, targetVillageId: village.id, units, orders: 'reinforce', at });
    } catch (error) {
      // No road there: this village can't help.
      if (!(error instanceof RuleError)) throw error;
    }
  }
  await notifyWorld(client, { worldId: world.id, type: 'armies' });
}

// Losses an army took: its supply is settled first (the dead stop eating),
// or, for an army from before supplies, its home village stops feeding them.
export async function armyLosses(client: DbClient, data: GameData, world: World, army: Army, losses: Record<string, number>, at: Date): Promise<Army> {
  if (total(losses) === 0) return army;
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
    if (army.status !== 'marching') return;
    if (army.orders === 'explore') {
      await arriveAtSite(client, data, world, army, event.dueAt);
      await notifyWorld(client, { worldId: world.id, type: 'armies' });
      return;
    }
    if (army.orders === 'clear') {
      await stormCamp(client, data, world, army, event.dueAt);
      await notifyWorld(client, { worldId: world.id, type: 'armies' });
      return;
    }
    if (army.orders === 'hold') {
      await saveArmy(client, { ...army, status: 'stationed' });
      const fort = await fortAt(client, world.id, army.targetQ, army.targetR);
      if (fort) await markFortManned(client, fort.id, event.dueAt);
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
    // Any village it reaches fills its supply.
    const arrived = await resupply(client, data, world, army, army.targetVillageId!, event.dueAt);
    const ongoing = rows[0] ? await loadBattle(client, rows[0].id) : null;
    if (ongoing?.waveId) {
      await joinBattle(client, data, world, arrived, ongoing, await loadWave(client, ongoing.waveId), event.dueAt);
    } else if (army.orders === 'support') {
      await planHunger(client, data, world, { ...arrived, status: 'stationed' }, event.dueAt);
    } else {
      await sendHome(client, world, arrived, event.dueAt, data);
    }
    await notifyWorld(client, { worldId: world.id, type: 'armies' });
  },

  async army_return({ client, data, world }, event) {
    const army = await loadArmy(client, armyPayload.parse(event.payload).armyId);
    if (army.status !== 'returning') return;
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
    // Standing in a village, it eats from the stores.
    let current: Army = army;
    if ((army.status === 'stationed' || army.status === 'engaged') && army.targetVillageId !== null) {
      current = await resupply(client, data, world, army, army.targetVillageId, event.dueAt);
      if (supplyLeft(data, supplied(current)!, event.dueAt, world.speed) > 0) return;
    }
    const strike = hungerStrikes(data, supplied(current)!, event.dueAt, world.speed);
    const name = (await loadVillage(client, army.homeVillageId).catch(() => null))?.name ?? '';
    const thinned = strike.lost ? current : await armyLosses(client, data, world, current, strike.losses, event.dueAt);
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
