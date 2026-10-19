// The Kalinov Bridge on the scheduler (PLAN.md §10): donations from the
// vault, quests completed by what happens in the world, and bridge_raised
// when a stage has been built.
import type { BridgeQuest, GameData } from '../data/index.js';
import { findBridge, loadBridge, saveBridge } from '../db/bridges.js';
import { notifyWorld } from '../db/notify.js';
import type { Db, DbClient } from '../db/pool.js';
import { loadVault, saveVault } from '../db/vaults.js';
import { getWorld, isMember, listMembers, spendEmbers, type World } from '../db/worlds.js';
import { ForbiddenError, RuleError } from '../errors.js';
import { completeQuest, currentStage, donate, isReady, raised, startRaising, type BridgeState } from '../sim/bridge.js';
import { withdraw } from '../sim/logistics.js';
import type { Resources } from '../sim/resources.js';
import { scheduleEvent, type HandlerRegistry, type SchedulerDeps } from './events.js';
import { tell } from './notices.js';
import { callRitualNight } from './ritual.js';
import { revealSite } from './sites.js';
import { withWorld } from './world.js';

// Saves the bridge, and starts raising the stage once nothing is missing.
async function settleBridge(client: DbClient, data: GameData, world: World, bridge: BridgeState, at: Date): Promise<BridgeState> {
  let next = bridge;
  if (isReady(data, next)) {
    next = startRaising(data, next, at, world.speed);
    await scheduleEvent(client, world.id, new Date(next.raisedAt!), 'bridge_raised', { stage: next.stage });
    for (const member of await listMembers(client, world.id)) {
      await tell(client, world, member.accountId, {
        kind: 'bridge',
        tier: 'digest',
        title: `Raising ${currentStage(data, next)!.name}`,
        body: 'Everything it needs is in place; the builders are at work.',
      }, at);
    }
  }
  await saveBridge(client, world.id, next);
  await notifyWorld(client, { worldId: world.id, type: 'world' });
  return next;
}

// Something happened that may answer a quest of the open stage.
export async function bridgeQuest(client: DbClient, data: GameData, world: World, quest: BridgeQuest, at: Date): Promise<void> {
  if (world.status !== 'running') return;
  const bridge = await loadBridge(client, world.id, at, (await getWorld(client, world.id)).sanctity);
  if (quest === 'unscathed') {
    const sanctity = (await getWorld(client, world.id)).sanctity;
    if (sanctity < bridge.sanctityAtStart) return;
  }
  const done = completeQuest(data, bridge, quest, at);
  if (!done) return;
  const stage = currentStage(data, done)!;
  for (const member of await listMembers(client, world.id)) {
    await tell(client, world, member.accountId, {
      kind: 'bridge',
      tier: 'digest',
      title: `${stage.name}: ${data.bridge.quests[quest].name}`,
      body: stage.quests.find((q) => q.kind === quest)?.story ?? '',
    }, at);
  }
  await settleBridge(client, data, world, done, at);
}

async function memberCommand<T>(
  db: Db,
  deps: SchedulerDeps,
  input: { accountId: number; worldId: number; now: Date },
  apply: (client: DbClient, world: World, bridge: BridgeState) => Promise<T>,
): Promise<T> {
  return withWorld(db, input.worldId, input.now, deps, async (client) => {
    if (!(await isMember(client, input.worldId, input.accountId))) throw new ForbiddenError('Not a member of this world');
    const world = await getWorld(client, input.worldId);
    if (world.status !== 'running') throw new RuleError('This world is not running');
    return apply(client, world, await loadBridge(client, world.id, input.now, world.sanctity));
  });
}

// Moves resources (and Ember) from the group's vault into the open stage,
// as much as it still needs.
export async function donateCommand(
  db: Db,
  deps: SchedulerDeps,
  input: { accountId: number; worldId: number; resources: Resources; embers: number; now: Date },
): Promise<BridgeState> {
  return memberCommand(db, deps, input, async (client, world, bridge) => {
    const vault = await loadVault(client, world.id);
    const fromVault = withdraw(vault.amounts, input.resources);
    if (input.embers > world.embers) throw new RuleError(`The group has ${world.embers} Svarog's Ember`);
    const result = donate(deps.data, bridge, { resources: fromVault.taken, embers: input.embers });
    await saveVault(client, { ...vault, amounts: withdraw(vault.amounts, result.taken).amounts });
    if (result.embers > 0 && !(await spendEmbers(client, world.id, result.embers))) throw new RuleError("Not enough Svarog's Ember");
    await notifyWorld(client, { worldId: world.id, type: 'caravans' });
    return settleBridge(client, deps.data, world, result.bridge, input.now);
  });
}

// Forges the ritual torc from the group's Ember (the ritual quest).
export async function craftRitualCommand(db: Db, deps: SchedulerDeps, input: { accountId: number; worldId: number; now: Date }): Promise<BridgeState> {
  return memberCommand(db, deps, input, async (client, world, bridge) => {
    const done = completeQuest(deps.data, bridge, 'ritual', input.now);
    if (!done) throw new RuleError('No stage needs the ritual torc now');
    if (!(await spendEmbers(client, world.id, deps.data.bridge.ritualEmbers))) {
      throw new RuleError(`The torc takes ${deps.data.bridge.ritualEmbers} Svarog's Ember`);
    }
    return settleBridge(client, deps.data, world, done, input.now);
  });
}

export const bridgeHandlers: HandlerRegistry = {
  async bridge_raised({ client, data, world }, event) {
    const bridge = await findBridge(client, world.id);
    if (!bridge || bridge.status !== 'raising' || !bridge.raisedAt || new Date(bridge.raisedAt) > event.dueAt) return;
    const name = currentStage(data, bridge)!.name;
    const next = raised(data, bridge, event.dueAt, world.sanctity);
    await saveBridge(client, world.id, next);
    for (const member of await listMembers(client, world.id)) {
      await tell(client, world, member.accountId, {
        kind: 'bridge',
        tier: 'push',
        title: `${name} stands`,
        body: next.status === 'complete' ? 'The Kalinov Bridge is whole. Ritual Night is coming.' : `Next: ${currentStage(data, next)!.name}.`,
      }, event.dueAt);
    }
    await notifyWorld(client, { worldId: world.id, type: 'world' });
    if (next.status === 'complete') await callRitualNight(client, data, world, event.dueAt);
    // A relic is wanted and every ruin has been searched: one more is remembered.
    const stage = currentStage(data, next);
    if (stage?.quests.some((q) => q.kind === 'site') && (await revealSite(client, data, world))) {
      for (const member of await listMembers(client, world.id)) {
        await tell(client, world, member.accountId, {
          kind: 'bridge',
          tier: 'digest',
          title: 'A forgotten ruin',
          body: `The builders of ${stage.name} remember a ruin nobody has searched yet. It is marked on the map.`,
        }, event.dueAt);
      }
    }
  },
};
