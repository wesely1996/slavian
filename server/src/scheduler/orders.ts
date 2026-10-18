// Standing orders on the scheduler: every few game minutes (orders_check)
// a village with orders runs them in turn, recording what each did.
import { z } from 'zod';
import type { GameData } from '../data/index.js';
import { dispatchCaravan } from '../commands/logistics.js';
import { caravansOut } from '../db/caravans.js';
import { countVillagesOwned } from '../db/expeditions.js';
import { effectiveBonuses } from '../db/heroes.js';
import { notifyWorld } from '../db/notify.js';
import { listOrders, recordOrderRun } from '../db/orders.js';
import type { DbClient } from '../db/pool.js';
import { loadVillage, saveVillageState, type Village } from '../db/villages.js';
import type { World } from '../db/worlds.js';
import { RuleError } from '../errors.js';
import { CARAVAN_YARD, caravanCapacity, caravansAt, total } from '../sim/logistics.js';
import { rebuildTargets, surplusLoad, trainCount, type StandingOrder } from '../sim/orders.js';
import { amountsAt, InsufficientResourcesError, spend } from '../sim/resources.js';
import { batchCompletesAt } from '../sim/training.js';
import { completeTraining, outpostHex, queueBuild, queueTraining, unitsFed, type VillageState } from '../sim/village.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';

export const ordersPayload = z.object({ villageId: z.number().int() });
export type OrdersPayload = z.infer<typeof ordersPayload>;

function checkMs(data: GameData, worldSpeed: number): number {
  return Math.round((data.orders.checkMinutes * 60_000) / worldSpeed);
}

// Makes sure the village's next orders_check is on the calendar.
export async function ensureOrdersCheck(client: DbClient, data: GameData, world: World, villageId: number, from: Date): Promise<void> {
  const { rows } = await client.query(
    `SELECT 1 FROM scheduled_events WHERE world_id = $1 AND type = 'orders_check' AND status = 'pending' AND payload @> $2::jsonb`,
    [world.id, JSON.stringify({ villageId })],
  );
  if (rows.length) return;
  const payload: OrdersPayload = { villageId };
  await scheduleEvent(client, world.id, new Date(from.getTime() + checkMs(data, world.speed)), 'orders_check', payload);
}

// One order's turn: the village state after it, and what happened.
async function runOrder(
  client: DbClient,
  data: GameData,
  world: World,
  village: Village,
  state: VillageState,
  spec: StandingOrder,
  at: Date,
): Promise<{ state: VillageState; result: string }> {
  if (spec.kind === 'rebuild') {
    const targets = rebuildTargets(state);
    if (!targets.length) return { state, result: 'Every outpost stands at its best' };
    const rebuilt: string[] = [];
    for (const plot of targets) {
      const { state: next, queued } = queueBuild(data, state, { plot }, at, world.speed);
      state = next;
      await scheduleEvent(client, world.id, queued.completesAt, 'build_complete', {
        villageId: village.id,
        plot: queued.plot,
        building: queued.building,
        targetLevel: queued.targetLevel,
      });
      const cell = outpostHex(plot)!;
      rebuilt.push(`(${cell.q}, ${cell.r})`);
    }
    return { state, result: `Rebuilding the outpost${rebuilt.length > 1 ? 's' : ''} at ${rebuilt.join(', ')}` };
  }

  if (spec.kind === 'train') {
    const name = data.units.units[spec.unit]?.name ?? spec.unit;
    const count = trainCount(spec, unitsFed(state)[spec.unit] ?? 0);
    if (count === 0) return { state, result: `${spec.target} ${name} kept` };
    const owned = await countVillagesOwned(client, world.id, village.ownerAccountId!);
    const { state: next, batch } = queueTraining(data, state, spec.unit, count, at, world.speed, owned);
    await scheduleEvent(client, world.id, batchCompletesAt(batch), 'training_complete', { villageId: village.id });
    return { state: next, result: `Training ${count} ${name}` };
  }

  const yard = state.levels[CARAVAN_YARD] ?? 0;
  if (yard < 1) throw new RuleError('Build a Caravan Yard first');
  const free = caravansAt(data, yard) - (await caravansOut(client, village.id));
  const capacity = caravanCapacity(data, await effectiveBonuses(client, data, { ...village, state }));
  const load = surplusLoad(data, amountsAt(state.ledger, at), state.ledger.capacity, spec.share, free * capacity);
  if (!load) {
    return { state, result: free > 0 ? `Nothing above ${Math.round(spec.share * 100)}% of storage` : 'All caravans are out' };
  }
  await dispatchCaravan(client, data, world, { ...village, state }, 'deliver', { destinationVillageId: null, load }, at);
  return { state: { ...state, ledger: spend(state.ledger, at, load) }, result: `Sent ${total(load)} to the vault` };
}

// Runs every order of a village once. Returns whether it has any.
export async function runOrders(client: DbClient, data: GameData, world: World, villageId: number, at: Date): Promise<boolean> {
  const orders = await listOrders(client, { villageId });
  if (!orders.length) return false;
  const village = await loadVillage(client, villageId);
  let state = completeTraining(village.state, at);
  for (const order of orders) {
    let result: string;
    try {
      ({ state, result } = await runOrder(client, data, world, village, state, order.spec, at));
    } catch (error) {
      if (!(error instanceof RuleError) && !(error instanceof InsufficientResourcesError)) throw error;
      result = error instanceof InsufficientResourcesError ? 'Waiting for resources' : `Waiting: ${error.message}`;
    }
    await recordOrderRun(client, order.id, result, at);
  }
  await saveVillageState(client, village.id, state);
  await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
  await notifyWorld(client, { worldId: world.id, type: 'orders' });
  return true;
}

export const orderHandlers: HandlerRegistry = {
  async orders_check({ client, data, world }, event) {
    const { villageId } = ordersPayload.parse(event.payload);
    if (!(await runOrders(client, data, world, villageId, event.dueAt))) return;
    const payload: OrdersPayload = { villageId };
    await scheduleEvent(client, world.id, new Date(event.dueAt.getTime() + checkMs(data, world.speed)), 'orders_check', payload);
  },
};
