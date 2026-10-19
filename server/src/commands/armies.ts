import { loadArmy, saveReinforceRule, type Army } from '../db/armies.js';
import type { StoredRiverEdge } from '../db/rivers.js';
import { authorize } from '../db/delegations.js';
import type { GameData } from '../data/index.js';
import { notifyWorld } from '../db/notify.js';
import { inTransaction, type Db } from '../db/pool.js';
import { loadVillage } from '../db/villages.js';
import { getWorld } from '../db/worlds.js';
import { NotFoundError, RuleError } from '../errors.js';
import { dispatchArmy, sendHome } from '../scheduler/armies.js';
import type { SchedulerDeps } from '../scheduler/events.js';
import { withWorld } from '../scheduler/world.js';
import type { ArmyOrders } from '../sim/armies.js';
import type { Hex } from '../sim/hex.js';
import type { Fort } from '../db/forts.js';
import { buildCrossing, buildFort } from '../scheduler/field.js';

async function worldOfVillage(db: Db, villageId: number): Promise<number> {
  const { rows } = await db.query<{ world_id: number }>('SELECT world_id FROM villages WHERE id = $1', [villageId]);
  if (!rows[0]) throw new NotFoundError(`Village ${villageId} not found`);
  return rows[0].world_id;
}

// Sends troops from the caller's village to another village, or to hold a hex.
export async function sendArmyCommand(
  db: Db,
  deps: SchedulerDeps,
  input: {
    accountId: number;
    villageId: number;
    targetVillageId: number | null;
    target?: Hex | undefined;
    units: Record<string, number>;
    orders: ArmyOrders;
    withHero?: boolean | undefined;
    now: Date;
  },
): Promise<Army> {
  const worldId = await worldOfVillage(db, input.villageId);
  return withWorld(db, worldId, input.now, deps, async (client) => {
    const home = await loadVillage(client, input.villageId);
    await authorize(client, { worldId, ownerAccountId: home.ownerAccountId, actorAccountId: input.accountId, at: input.now, action: 'sent an army', villageId: home.id });
    return dispatchArmy(client, deps.data, await getWorld(client, worldId), {
      homeVillageId: home.id,
      targetVillageId: input.targetVillageId,
      targetHex: input.target,
      units: input.units,
      orders: input.orders,
      withHero: input.withHero,
      at: input.now,
    });
  });
}

// Builds a fort near the caller's village.
export async function buildFortCommand(db: Db, deps: SchedulerDeps, input: { accountId: number; villageId: number; cell: Hex; now: Date }): Promise<Fort> {
  const worldId = await worldOfVillage(db, input.villageId);
  return withWorld(db, worldId, input.now, deps, async (client) => {
    const village = await loadVillage(client, input.villageId);
    await authorize(client, { worldId, ownerAccountId: village.ownerAccountId, actorAccountId: input.accountId, at: input.now, action: 'built a fort', villageId: village.id });
    return buildFort(client, deps.data, await getWorld(client, worldId), village.id, input.cell, input.now);
  });
}

// Builds a bridge over a river edge near the caller's village.
export async function buildCrossingCommand(
  db: Db,
  deps: SchedulerDeps,
  input: { accountId: number; villageId: number; a: Hex; b: Hex; now: Date },
): Promise<StoredRiverEdge> {
  const worldId = await worldOfVillage(db, input.villageId);
  return withWorld(db, worldId, input.now, deps, async (client) => {
    const village = await loadVillage(client, input.villageId);
    await authorize(client, { worldId, ownerAccountId: village.ownerAccountId, actorAccountId: input.accountId, at: input.now, action: 'built a bridge', villageId: village.id });
    return buildCrossing(client, deps.data, await getWorld(client, worldId), village.id, input.a, input.b, input.now);
  });
}

// Calls an army standing guard or holding a hex home (not in the middle of a battle).
export async function recallArmyCommand(db: Db, deps: SchedulerDeps, input: { accountId: number; armyId: number; now: Date }): Promise<Army> {
  const { rows } = await db.query<{ world_id: number }>('SELECT world_id FROM armies WHERE id = $1', [input.armyId]);
  if (!rows[0]) throw new NotFoundError('No such army');
  return withWorld(db, rows[0].world_id, input.now, deps, async (client) => {
    const army = await loadArmy(client, input.armyId);
    await authorize(client, {
      worldId: army.worldId,
      ownerAccountId: army.ownerAccountId,
      actorAccountId: input.accountId,
      at: input.now,
      action: 'called an army home',
      villageId: army.homeVillageId,
      refusal: 'Not your army',
    });
    if (army.status === 'engaged') throw new RuleError('That army is in the middle of a battle');
    if (army.status !== 'stationed') throw new RuleError('Only armies standing guard can be called home');
    const back = await sendHome(client, await getWorld(client, army.worldId), army, input.now, deps.data);
    await notifyWorld(client, { worldId: army.worldId, type: 'armies' });
    return back;
  });
}

// How a village answers battles nearby.
export async function setReinforceCommand(
  db: Db,
  data: GameData,
  input: { accountId: number; villageId: number; share: number; range: number },
): Promise<void> {
  const worldId = await worldOfVillage(db, input.villageId);
  if (!(input.share >= 0 && input.share <= 1)) throw new RuleError('Send between 0% and 100%');
  if (!Number.isInteger(input.range) || input.range < 0 || input.range > data.armies.reinforce.maxRange) {
    throw new RuleError(`Range is 0 to ${data.armies.reinforce.maxRange} hexes`);
  }
  await inTransaction(db, async (client) => {
    const village = await loadVillage(client, input.villageId);
    await authorize(client, { worldId, ownerAccountId: village.ownerAccountId, actorAccountId: input.accountId, at: new Date(), action: 'changed how it reinforces', villageId: village.id });
    await saveReinforceRule(client, input.villageId, { share: input.share, range: input.range });
    await notifyWorld(client, { worldId, type: 'village', villageId: input.villageId });
  });
}
