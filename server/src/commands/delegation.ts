// Delegation (PLAN.md Q23): a player hands a teammate their villages for
// 1–7 days, while away. The delegate commands them as their own; each
// action is logged for the owner (db/delegations.ts).
import { activeDelegations, endDelegation, setDelegation } from '../db/delegations.js';
import { notifyWorld } from '../db/notify.js';
import type { Db } from '../db/pool.js';
import { getWorld, listMembers } from '../db/worlds.js';
import { ForbiddenError, RuleError } from '../errors.js';
import type { SchedulerDeps } from '../scheduler/events.js';
import { tell } from '../scheduler/notices.js';
import { withWorld } from '../scheduler/world.js';

export const MAX_DELEGATION_DAYS = 7;
const MS_PER_DAY = 86_400_000;

export async function delegateCommand(
  db: Db,
  deps: SchedulerDeps,
  input: { accountId: number; worldId: number; to: number; days: number; now: Date },
): Promise<void> {
  if (!Number.isInteger(input.days) || input.days < 1 || input.days > MAX_DELEGATION_DAYS) {
    throw new RuleError(`Hand over for 1 to ${MAX_DELEGATION_DAYS} days`);
  }
  await withWorld(db, input.worldId, input.now, deps, async (client) => {
    const world = await getWorld(client, input.worldId);
    if (world.status !== 'running') throw new RuleError('This world is not running');
    const members = await listMembers(client, world.id);
    const me = members.find((m) => m.accountId === input.accountId);
    if (!me) throw new ForbiddenError('You are not in this world');
    const delegate = members.find((m) => m.accountId === input.to);
    if (!delegate) throw new RuleError('Hand over to someone in this world');
    if (delegate.accountId === me.accountId) throw new RuleError('Pick a teammate, not yourself');
    // No chains: someone away can't be handed more villages to look after.
    if ((await activeDelegations(client, world.id, input.now)).some((d) => d.ownerAccountId === delegate.accountId)) {
      throw new RuleError(`${delegate.displayName} has handed over their own villages`);
    }
    const until = new Date(input.now.getTime() + input.days * MS_PER_DAY);
    await setDelegation(client, world.id, { ownerAccountId: me.accountId, delegateAccountId: delegate.accountId, since: input.now, until });
    await tell(client, world, delegate.accountId, {
      kind: 'delegation',
      tier: 'push',
      title: `${me.displayName} handed you their villages`,
      body: `Command them as your own for ${input.days} day${input.days === 1 ? '' : 's'}. Everything you do is noted for them.`,
    }, input.now);
    await notifyWorld(client, { worldId: world.id, type: 'world' });
  });
}

// The owner takes their villages back (or the delegate hands them back).
export async function endDelegationCommand(
  db: Db,
  deps: SchedulerDeps,
  input: { accountId: number; worldId: number; owner?: number | undefined; now: Date },
): Promise<void> {
  await withWorld(db, input.worldId, input.now, deps, async (client) => {
    const world = await getWorld(client, input.worldId);
    const owner = input.owner ?? input.accountId;
    const delegation = (await activeDelegations(client, world.id, input.now)).find((d) => d.ownerAccountId === owner);
    if (!delegation || (owner !== input.accountId && delegation.delegateAccountId !== input.accountId)) {
      throw new RuleError('There is no hand-over to end');
    }
    await endDelegation(client, world.id, owner);
    const other = owner === input.accountId ? delegation.delegateAccountId : owner;
    const name = (await listMembers(client, world.id)).find((m) => m.accountId === input.accountId)?.displayName ?? 'A teammate';
    await tell(client, world, other, {
      kind: 'delegation',
      tier: 'digest',
      title: owner === input.accountId ? `${name} took their villages back` : `${name} handed your villages back`,
      body: 'The hand-over has ended.',
    }, input.now);
    await notifyWorld(client, { worldId: world.id, type: 'world' });
  });
}
