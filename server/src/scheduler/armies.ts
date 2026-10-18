// Armies on the scheduler: army_arrive (station, join a battle, or turn
// back), army_return (home again). Battles (battles.ts) use the helpers here
// to fold armies into the defenders and to call in reinforcements.
import { z } from 'zod';
import type { GameData, TerrainId } from '../data/index.js';
import { armiesAt, insertArmy, loadArmy, loadReinforceRule, saveArmy, type Army } from '../db/armies.js';
import { addDefenders, loadBattle, type Battle } from '../db/battles.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { listVillages, loadVillage, saveVillageState, type Village } from '../db/villages.js';
import { loadWave, type Wave } from '../db/waves.js';
import { loadHexes, type World } from '../db/worlds.js';
import { RuleError } from '../errors.js';
import { approachAngle, armySpeed, joinBonus, shareOf, total, validateArmy, type ArmyOrders } from '../sim/armies.js';
import { hex, hexDistance } from '../sim/hex.js';
import { roadRoute } from '../sim/logistics.js';
import { completeTraining, loseAway, returnHome, sendAway } from '../sim/village.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';

export const armyPayload = z.object({ armyId: z.number().int() });
export type ArmyPayload = z.infer<typeof armyPayload>;

async function terrainOf(client: DbClient, worldId: number): Promise<Map<string, TerrainId>> {
  return new Map((await loadHexes(client, worldId)).map(([q, r, t]) => [`${q},${r}`, t]));
}

// Sends troops from a village to another as an army.
export async function dispatchArmy(
  client: DbClient,
  data: GameData,
  world: World,
  input: { homeVillageId: number; targetVillageId: number; units: Record<string, number>; orders: ArmyOrders; at: Date },
): Promise<Army> {
  if (input.homeVillageId === input.targetVillageId) throw new RuleError('Send them to another village');
  const units = validateArmy(data, input.units, input.orders);
  const home = await loadVillage(client, input.homeVillageId);
  const target = await loadVillage(client, input.targetVillageId).catch(() => null);
  if (!target || target.worldId !== world.id) throw new RuleError('No such village in this world');
  let state = completeTraining(home.state, input.at);
  for (const [unit, n] of Object.entries(units)) state = sendAway(state, unit, n, input.at);
  const path = roadRoute(data, await terrainOf(client, world.id), hex(home.q, home.r), hex(target.q, target.r), armySpeed(data, units), world.speed);
  const army = await insertArmy(client, {
    worldId: world.id,
    ownerAccountId: home.ownerAccountId,
    homeVillageId: home.id,
    targetVillageId: target.id,
    orders: input.orders,
    units,
    path,
    departsAt: input.at,
    arrivesAt: new Date(input.at.getTime() + path.at(-1)!.atMs),
  });
  await saveVillageState(client, home.id, state);
  const payload: ArmyPayload = { armyId: army.id };
  await scheduleEvent(client, world.id, army.arrivesAt, 'army_arrive', payload);
  await notifyWorld(client, { worldId: world.id, type: 'village', villageId: home.id });
  await notifyWorld(client, { worldId: world.id, type: 'armies' });
  return army;
}

// Turns an army for home, along the road it came.
export async function sendHome(client: DbClient, world: World, army: Army, at: Date): Promise<Army> {
  if (total(army.units) === 0) {
    const gone: Army = { ...army, status: 'done', battleId: null, leavesAt: at, returnsAt: at };
    await saveArmy(client, gone);
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

// An army joins the battle at its target from the next round.
async function joinBattle(client: DbClient, data: GameData, army: Army, battle: Battle, wave: Wave): Promise<Army> {
  const target = await loadVillage(client, army.targetVillageId);
  const villageHex = hex(target.q, target.r);
  const hordeStep = wave.path?.at(-2);
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
    const { rows } = await client.query<{ id: number }>(
      `SELECT id FROM battles WHERE village_id = $1 AND status = 'ongoing' LIMIT 1`,
      [army.targetVillageId],
    );
    if (rows[0]) {
      const battle = await loadBattle(client, rows[0].id);
      await joinBattle(client, data, army, battle, await loadWave(client, battle.waveId));
    } else if (army.orders === 'support') {
      await saveArmy(client, { ...army, status: 'stationed' });
    } else {
      await sendHome(client, world, army, event.dueAt);
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
    await notifyWorld(client, { worldId: world.id, type: 'village', villageId: home.id });
    await notifyWorld(client, { worldId: world.id, type: 'armies' });
  },
};
