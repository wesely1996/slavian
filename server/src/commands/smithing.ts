// The Blacksmith (data/smithing.json): a player starts forging an
// improvement for one of their units, from a village with a Blacksmith,
// paid from its stores; one at a time per player.
import type { Db } from '../db/pool.js';
import { listMembers, setSmithing } from '../db/worlds.js';
import { notifyWorld } from '../db/notify.js';
import { RuleError } from '../errors.js';
import { scheduleEvent, type SchedulerDeps } from '../scheduler/events.js';
import { villageBonuses } from '../sim/clans.js';
import { spend } from '../sim/resources.js';
import { BLACKSMITH, nextSmithLevel, smithCost, smithMs, type SmithWork } from '../sim/smithing.js';
import type { SmithLine } from '../data/index.js';
import type { Village } from '../db/villages.js';
import { ownVillageCommand, type VillageCommandInput } from './village.js';

export async function startSmithingCommand(
  db: Db,
  deps: SchedulerDeps,
  input: VillageCommandInput & { unit: string; line: string },
): Promise<{ village: Village; work: SmithWork }> {
  const { village, result } = await ownVillageCommand(db, deps, { ...input, action: 'set the Blacksmith to work' }, async ({ client, world, village }) => {
    const smithy = village.state.levels[BLACKSMITH] ?? 0;
    if (smithy < 1) throw new RuleError('Build a Blacksmith first');
    const member = (await listMembers(client, world.id)).find((m) => m.accountId === village.ownerAccountId);
    if (!member) throw new RuleError('Only a member of this world can forge');
    const level = nextSmithLevel(deps.data, member.smithing, input.unit, input.line, smithy, member.smithWork !== null);
    const cost = smithCost(deps.data, input.unit, input.line as SmithLine, level);
    const ledger = spend(village.state.ledger, input.now, cost);
    const completesAt = new Date(input.now.getTime() + smithMs(deps.data, input.unit, input.line as SmithLine, level, world.speed, villageBonuses(deps.data, village.state)));
    const work: SmithWork = { unit: input.unit, line: input.line as SmithLine, level, villageId: village.id, completesAt: completesAt.toISOString() };
    await setSmithing(client, world.id, member.accountId, member.smithing, work);
    await scheduleEvent(client, world.id, completesAt, 'smith_done', { accountId: member.accountId });
    await notifyWorld(client, { worldId: world.id, type: 'world' });
    return { state: { ...village.state, ledger }, result: work };
  });
  return { village, work: result };
}
