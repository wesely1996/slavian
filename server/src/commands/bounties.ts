// The Market's bounty board (sim/bounties.ts): post a bounty from a village
// with a Market, call it off, or take another player's at once.
import { closeBounty, insertBounty, loadBounty, openBountiesOf, type Bounty } from '../db/bounties.js';
import { notifyWorld } from '../db/notify.js';
import type { Db } from '../db/pool.js';
import { loadVillage, saveVillageState, type Village } from '../db/villages.js';
import { NotFoundError, RuleError } from '../errors.js';
import type { SchedulerDeps } from '../scheduler/events.js';
import { tell } from '../scheduler/notices.js';
import { bountyFee, bountyReturn, checkBounty } from '../sim/bounties.js';
import { receive, total } from '../sim/logistics.js';
import { mapResources, spend, type Resources } from '../sim/resources.js';
import { MARKET } from '../sim/village.js';
import { ownVillageCommand, type VillageCommandInput } from './village.js';

// Posts a bounty: what it offers and the fee on it leave the stores now.
export async function postBountyCommand(
  db: Db,
  deps: SchedulerDeps,
  input: VillageCommandInput & { offer: Resources; want: Resources },
): Promise<{ village: Village; bounty: Bounty }> {
  const { village, result } = await ownVillageCommand(db, deps, { ...input, action: 'posted a bounty' }, async ({ client, world, village }) => {
    checkBounty(deps.data, village.state.levels[MARKET] ?? 0, await openBountiesOf(client, village.id), input.offer, input.want);
    const fee = bountyFee(deps.data, input.offer);
    const ledger = spend(village.state.ledger, input.now, mapResources((k) => input.offer[k] + fee[k]));
    const bounty = await insertBounty(client, {
      worldId: world.id,
      villageId: village.id,
      ownerAccountId: village.ownerAccountId,
      offer: input.offer,
      want: input.want,
      fee,
      createdAt: input.now,
    });
    await notifyWorld(client, { worldId: world.id, type: 'caravans' });
    return { state: { ...village.state, ledger }, result: bounty };
  });
  return { village, bounty: result };
}

async function bountyOf(db: Db, id: number): Promise<Bounty> {
  const client = await db.connect();
  try {
    const bounty = await loadBounty(client, id);
    if (!bounty) throw new NotFoundError('No such bounty');
    return bounty;
  } finally {
    client.release();
  }
}

// Calls a bounty off: what it offered comes back (the fee does not).
export async function cancelBountyCommand(db: Db, deps: SchedulerDeps, input: { accountId: number; bountyId: number; now: Date }): Promise<{ village: Village }> {
  const found = await bountyOf(db, input.bountyId);
  const { village } = await ownVillageCommand(
    db,
    deps,
    { accountId: input.accountId, villageId: found.villageId, now: input.now, allowRuin: true, action: 'called off a bounty' },
    async ({ client, world, village }) => {
      const bounty = (await loadBounty(client, found.id))!;
      if (bounty.status !== 'open') throw new RuleError('That bounty is closed');
      await closeBounty(client, bounty.id, 'cancelled', input.now, null);
      await notifyWorld(client, { worldId: world.id, type: 'caravans' });
      return { state: { ...village.state, ledger: receive(village.state.ledger, input.now, bounty.offer).ledger }, result: null };
    },
  );
  return { village };
}

// Takes another player's bounty from one of the caller's villages: it pays
// what is asked and gets what is offered at once; the poster's village
// gets what was asked, less the fee.
export async function takeBountyCommand(
  db: Db,
  deps: SchedulerDeps,
  input: VillageCommandInput & { bountyId: number },
): Promise<{ village: Village }> {
  const { village } = await ownVillageCommand(db, deps, { ...input, action: 'took a bounty' }, async ({ client, world, village }) => {
    const bounty = await loadBounty(client, input.bountyId);
    if (!bounty || bounty.worldId !== world.id) throw new NotFoundError('No such bounty');
    if (bounty.status !== 'open') throw new RuleError('That bounty is closed');
    if (bounty.ownerAccountId === village.ownerAccountId) throw new RuleError('That bounty is your own');
    const paid = spend(village.state.ledger, input.now, bounty.want);
    const ledger = receive(paid, input.now, bounty.offer).ledger;
    const poster = await loadVillage(client, bounty.villageId);
    const back = bountyReturn(deps.data, bounty.want);
    await saveVillageState(client, poster.id, { ...poster.state, ledger: receive(poster.state.ledger, input.now, back).ledger });
    await closeBounty(client, bounty.id, 'taken', input.now, village.id);
    await notifyWorld(client, { worldId: world.id, type: 'village', villageId: poster.id });
    await notifyWorld(client, { worldId: world.id, type: 'caravans' });
    await tell(client, world, poster.ownerAccountId, {
      kind: 'caravan_delivered',
      tier: 'digest',
      title: 'Your bounty from {village} was taken',
      body: '{taker} paid {amount} resources for it.',
      vars: { village: poster.name, taker: village.name, amount: total(back) },
    }, input.now);
    return { state: { ...village.state, ledger }, result: null };
  });
  return { village };
}
