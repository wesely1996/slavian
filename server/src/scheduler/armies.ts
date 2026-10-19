// Armies on the scheduler: army_arrive (station, join a battle, hold a hex,
// or turn back), army_return (home again). Battles (battles.ts, field.ts)
// use the helpers here to fold armies into the defenders and to call in
// reinforcements.
import { z } from 'zod';
import type { GameData, TerrainId } from '../data/index.js';
import { armiesAt, insertArmy, loadArmy, loadReinforceRule, saveArmy, type Army } from '../db/armies.js';
import { addDefenders, loadBattle, type Battle } from '../db/battles.js';
import { heroWithArmy, loadHero, saveHero } from '../db/heroes.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { listVillages, loadVillage, saveVillageState, type Village } from '../db/villages.js';
import { loadWave, type Wave } from '../db/waves.js';
import { loadHexes, type World } from '../db/worlds.js';
import { RuleError } from '../errors.js';
import { approachAngle, armySpeed, joinBonus, shareOf, total, validateArmy, type ArmyOrders } from '../sim/armies.js';
import { hex, hexDistance, type Hex } from '../sim/hex.js';
import { woundMs } from '../sim/heroes.js';
import { roadRoute } from '../sim/logistics.js';
import { completeTraining, loseAway, returnHome, sendAway } from '../sim/village.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';
import { interceptAt } from './field.js';
import { deliverLoot, stormCamp } from './camps.js';
import { campAt } from '../db/camps.js';
import { fortAt, markFortManned } from '../db/forts.js';

export const armyPayload = z.object({ armyId: z.number().int() });
export type ArmyPayload = z.infer<typeof armyPayload>;

export async function terrainOf(client: DbClient, worldId: number): Promise<Map<string, TerrainId>> {
  return new Map((await loadHexes(client, worldId)).map(([q, r, t]) => [`${q},${r}`, t]));
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
  at: Date;
}

// Sends troops from a village as an army.
export async function dispatchArmy(client: DbClient, data: GameData, world: World, input: ArmyOrder): Promise<Army> {
  const units = validateArmy(data, input.units, input.orders);
  const home = await loadVillage(client, input.homeVillageId);
  let to: Hex;
  if (input.orders === 'clear') {
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
    to = hex(target.q, target.r);
  }
  let state = completeTraining(home.state, input.at);
  for (const [unit, n] of Object.entries(units)) state = sendAway(state, unit, n, input.at);
  const path = roadRoute(data, await terrainOf(client, world.id), hex(home.q, home.r), to, armySpeed(data, units), world.speed);

  let heroAccountId: number | null = null;
  if (input.withHero) {
    const hero = await loadHero(client, world.id, home.ownerAccountId!);
    if (hero.status !== 'home' || hero.villageId !== home.id) throw new RuleError(`${hero.name} is not ready in ${home.name}`);
    if (home.state.besieged) throw new RuleError(`${hero.name} won't leave in the middle of a battle`);
    heroAccountId = hero.accountId;
  }
  const army = await insertArmy(client, {
    worldId: world.id,
    ownerAccountId: home.ownerAccountId,
    homeVillageId: home.id,
    targetVillageId: input.orders === 'hold' || input.orders === 'clear' ? null : input.targetVillageId,
    targetQ: to.q,
    targetR: to.r,
    heroAccountId,
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
  await saveVillageState(client, home.id, state);
  const payload: ArmyPayload = { armyId: army.id };
  await scheduleEvent(client, world.id, army.arrivesAt, 'army_arrive', payload);
  await notifyWorld(client, { worldId: world.id, type: 'village', villageId: home.id });
  await notifyWorld(client, { worldId: world.id, type: 'armies' });
  return army;
}

// Turns an army for home, along the road it came. An army with no one left
// is done; its hero is carried home wounded.
export async function sendHome(client: DbClient, world: World, army: Army, at: Date, data?: GameData): Promise<Army> {
  if (total(army.units) === 0) {
    const gone: Army = { ...army, status: 'done', battleId: null, leavesAt: at, returnsAt: at };
    await saveArmy(client, gone);
    const hero = await heroWithArmy(client, army.id);
    if (hero && data) {
      const woundedUntil = new Date(at.getTime() + woundMs(data, world.speed));
      await saveHero(client, { ...hero, status: 'wounded', villageId: army.homeVillageId, armyId: null, woundedUntil });
      await scheduleEvent(client, world.id, woundedUntil, 'hero_recover', { accountId: hero.accountId });
      await notifyWorld(client, { worldId: world.id, type: 'heroes' });
    }
    return gone;
  }
  const back: Army = {
    ...army,
    status: 'returning',
    battleId: null,
    leavesAt: at,
    returnsAt: new Date(at.getTime() + army.path.at(-1)!.atMs),
  };
  await saveArmy(client, back);
  const payload: ArmyPayload = { armyId: army.id };
  await scheduleEvent(client, world.id, back.returnsAt!, 'army_return', payload);
  return back;
}

// An army joins the battle at its target village from the next round.
async function joinBattle(client: DbClient, data: GameData, army: Army, battle: Battle, wave: Wave): Promise<Army> {
  const villageHex = hex(battle.q, battle.r);
  const hordeStep = wave.path?.filter((s) => s.q !== battle.q || s.r !== battle.r).at(-1);
  const armyStep = army.path.at(-2);
  const angle = hordeStep && armyStep ? approachAngle(villageHex, hex(hordeStep.q, hordeStep.r), hex(armyStep.q, armyStep.r)) : 0;
  const bonus = joinBonus(data, { orders: army.orders, armySize: total(army.units), hordeSize: total(wave.composition), angle });
  const joined: Army = { ...army, status: 'engaged', battleId: battle.id, joinsRound: battle.round + 1, joinBonus: bonus };
  await saveArmy(client, joined);
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

// Losses an army took in a round: its home village stops feeding the dead.
export async function armyLosses(client: DbClient, data: GameData, world: World, army: Army, losses: Record<string, number>, at: Date): Promise<Army> {
  if (total(losses) === 0) return army;
  const home = await loadVillage(client, army.homeVillageId);
  let state = home.state;
  for (const [unit, n] of Object.entries(losses)) state = loseAway(data, state, unit, n, at, world.speed);
  await saveVillageState(client, home.id, state);
  await notifyWorld(client, { worldId: world.id, type: 'village', villageId: home.id });
  const units: Record<string, number> = {};
  for (const [unit, n] of Object.entries(army.units)) if (n - (losses[unit] ?? 0) > 0) units[unit] = n - (losses[unit] ?? 0);
  return { ...army, units };
}

export const armyHandlers: HandlerRegistry = {
  async army_arrive({ client, data, world }, event) {
    const army = await loadArmy(client, armyPayload.parse(event.payload).armyId);
    if (army.status !== 'marching') return;
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
    const ongoing = rows[0] ? await loadBattle(client, rows[0].id) : null;
    if (ongoing?.waveId) {
      await joinBattle(client, data, army, ongoing, await loadWave(client, ongoing.waveId));
    } else if (army.orders === 'support') {
      await saveArmy(client, { ...army, status: 'stationed' });
    } else {
      await sendHome(client, world, army, event.dueAt, data);
    }
    await notifyWorld(client, { worldId: world.id, type: 'armies' });
  },

  async army_return({ client, world }, event) {
    const army = await loadArmy(client, armyPayload.parse(event.payload).armyId);
    if (army.status !== 'returning') return;
    const home = await loadVillage(client, army.homeVillageId);
    let state = home.state;
    for (const [unit, n] of Object.entries(army.units)) state = returnHome(state, unit, n);
    await saveVillageState(client, home.id, state);
    await saveArmy(client, { ...army, status: 'done' });
    // Loot from a cleared camp goes into the stores.
    await deliverLoot(client, world, { ...army, status: 'done' }, event.dueAt);
    const hero = await heroWithArmy(client, army.id);
    if (hero) {
      await saveHero(client, { ...hero, status: 'home', villageId: home.id, armyId: null });
      await notifyWorld(client, { worldId: world.id, type: 'heroes' });
    }
    await notifyWorld(client, { worldId: world.id, type: 'village', villageId: home.id });
    await notifyWorld(client, { worldId: world.id, type: 'armies' });
  },
};
