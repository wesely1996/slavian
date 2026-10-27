import { loadFort } from '../db/forts.js';
import { deleteOrder, insertOrder, listOrders, type StoredOrder } from '../db/orders.js';
import { authorize } from '../db/delegations.js';
import { notifyWorld } from '../db/notify.js';
import type { Db } from '../db/pool.js';
import { loadVillage, type Village } from '../db/villages.js';
import { getWorld } from '../db/worlds.js';
import { NotFoundError, RuleError } from '../errors.js';
import type { SchedulerDeps } from '../scheduler/events.js';
import { ensureOrdersCheck, runOrders } from '../scheduler/orders.js';
import { withWorld } from '../scheduler/world.js';
import { validateOrder, type StandingOrder } from '../sim/orders.js';

interface OrderInput {
  accountId: number;
  villageId: number;
  now: Date;
}

async function worldOf(db: Db, villageId: number): Promise<number> {
  const { rows } = await db.query<{ world_id: number }>('SELECT world_id FROM villages WHERE id = $1', [villageId]);
  if (!rows[0]) throw new NotFoundError(`Village ${villageId} not found`);
  return rows[0].world_id;
}

// Places a standing order and runs it right away; it then runs every few
// game minutes until cancelled.
export async function placeOrderCommand(
  db: Db,
  deps: SchedulerDeps,
  input: OrderInput & { spec: StandingOrder },
): Promise<{ village: Village; order: StoredOrder }> {
  const worldId = await worldOf(db, input.villageId);
  return withWorld(db, worldId, input.now, deps, async (client) => {
    const world = await getWorld(client, worldId);
    const village = await loadVillage(client, input.villageId);
    await authorize(client, { worldId, ownerAccountId: village.ownerAccountId, actorAccountId: input.accountId, at: input.now, action: 'placed a standing order', villageId: village.id });
    const spec = validateOrder(deps.data, input.spec);
    const existing = await listOrders(client, { villageId: village.id });
    if (existing.length >= deps.data.orders.maxPerVillage) {
      throw new RuleError(`A village keeps at most ${deps.data.orders.maxPerVillage} standing orders`);
    }
    if (spec.kind === 'supply') {
      const fort = await loadFort(client, spec.fortId);
      if (!fort || fort.worldId !== worldId || fort.ownerAccountId !== village.ownerAccountId) throw new RuleError('No fort or supply point of yours there');
    }
    const same = existing.find(
      (o) =>
        o.spec.kind === spec.kind &&
        (spec.kind !== 'train' || (o.spec.kind === 'train' && o.spec.unit === spec.unit)) &&
        (spec.kind !== 'supply' || (o.spec.kind === 'supply' && o.spec.fortId === spec.fortId)),
    );
    if (same) throw new RuleError('This village already has that order; cancel it first');
    const order = await insertOrder(client, { worldId, villageId: village.id, spec, createdAt: input.now });
    await runOrders(client, deps.data, world, village.id, input.now);
    await ensureOrdersCheck(client, deps.data, world, village.id, input.now);
    const ran = (await listOrders(client, { villageId: village.id })).find((o) => o.id === order.id)!;
    return { village: await loadVillage(client, village.id), order: ran };
  });
}

export async function cancelOrderCommand(db: Db, deps: SchedulerDeps, input: OrderInput & { orderId: number }): Promise<void> {
  const worldId = await worldOf(db, input.villageId);
  await withWorld(db, worldId, input.now, deps, async (client) => {
    const village = await loadVillage(client, input.villageId);
    await authorize(client, { worldId, ownerAccountId: village.ownerAccountId, actorAccountId: input.accountId, at: input.now, action: 'cancelled a standing order', villageId: village.id });
    if (!(await deleteOrder(client, village.id, input.orderId))) throw new NotFoundError('No such order');
    await notifyWorld(client, { worldId, type: 'orders' });
  });
}
