import { loadArmy, saveReinforceRule, type Army } from '../db/armies.js';
import type { GameData } from '../data/index.js';
import { notifyWorld } from '../db/notify.js';
import { inTransaction, type Db } from '../db/pool.js';
import { loadVillage } from '../db/villages.js';
import { getWorld } from '../db/worlds.js';
import { ForbiddenError, NotFoundError, RuleError } from '../errors.js';
import { dispatchArmy, sendHome } from '../scheduler/armies.js';
import type { SchedulerDeps } from '../scheduler/events.js';
import { withWorld } from '../scheduler/world.js';
import type { ArmyOrders } from '../sim/armies.js';

async function worldOfVillage(db: Db, villageId: number): Promise<number> {
  const { rows } = await db.query<{ world_id: number }>('SELECT world_id FROM villages WHERE id = $1', [villageId]);
  if (!rows[0]) throw new NotFoundError(`Village ${villageId} not found`);
  return rows[0].world_id;
}

// Sends troops from the caller's village to another village.
export async function sendArmyCommand(
  db: Db,
  deps: SchedulerDeps,
  input: { accountId: number; villageId: number; targetVillageId: number; units: Record<string, number>; orders: ArmyOrders; now: Date },
): Promise<Army> {
  const worldId = await worldOfVillage(db, input.villageId);
  return withWorld(db, worldId, input.now, deps, async (client) => {
    const home = await loadVillage(client, input.villageId);
    if (home.ownerAccountId !== input.accountId) throw new ForbiddenError('Not your village');
    return dispatchArmy(client, deps.data, await getWorld(client, worldId), { homeVillageId: home.id, ...input, at: input.now });
  });
}

// Calls a supporting army home (not in the middle of a battle).
export async function recallArmyCommand(db: Db, deps: SchedulerDeps, input: { accountId: number; armyId: number; now: Date }): Promise<Army> {
  const { rows } = await db.query<{ world_id: number }>('SELECT world_id FROM armies WHERE id = $1', [input.armyId]);
  if (!rows[0]) throw new NotFoundError('No such army');
  return withWorld(db, rows[0].world_id, input.now, deps, async (client) => {
    const army = await loadArmy(client, input.armyId);
    if (army.ownerAccountId !== input.accountId) throw new ForbiddenError('Not your army');
    if (army.status === 'engaged') throw new RuleError('That army is in the middle of a battle');
    if (army.status !== 'stationed') throw new RuleError('Only armies standing guard can be called home');
    const back = await sendHome(client, await getWorld(client, army.worldId), army, input.now);
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
    if (village.ownerAccountId !== input.accountId) throw new ForbiddenError('Not your village');
    await saveReinforceRule(client, input.villageId, { share: input.share, range: input.range });
    await notifyWorld(client, { worldId, type: 'village', villageId: input.villageId });
  });
}
