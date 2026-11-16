// The getting-started chain (data/onboarding.json): the first time a player
// does each step it is marked done, and its reward waits on the quest card
// until they claim it. It goes to their first village, and claiming the last
// one brings the chain's own reward too.
import type { GameData, OnboardingStep } from '../data/index.js';
import { ForbiddenError, RuleError } from '../errors.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { listVillages, saveVillageState } from '../db/villages.js';
import { listMembers, markClaimed, markOnboarding, type World } from '../db/worlds.js';
import { mapResources, settle, type Resources } from '../sim/resources.js';
import { grantBuilding } from '../sim/village.js';
import { tell } from './notices.js';

export async function onboardingStep(
  client: DbClient,
  data: GameData,
  world: World,
  accountId: number | null,
  step: OnboardingStep,
  at: Date,
): Promise<void> {
  if (accountId === null || world.status !== 'running') return;
  const def = data.onboarding.steps.find((s) => s.id === step);
  if (!def || !(await markOnboarding(client, world.id, accountId, step, at))) return;
  await tell(client, world, accountId, {
    kind: 'onboarding',
    tier: 'digest',
    title: 'Done: {step}',
    body: 'Claim its reward from the quest card.',
    vars: { step: def.title },
  }, at);
  await notifyWorld(client, { worldId: world.id, type: 'world' });
}

// Gives a reward to the player's first standing village, all of it (a
// reward may fill the stores past their capacity). Returns that village's id.
export async function reward(client: DbClient, world: World, accountId: number, amounts: Resources, at: Date): Promise<number | null> {
  const home = (await listVillages(client, world.id)).filter((v) => v.ownerAccountId === accountId && !v.ruin).sort((a, b) => a.id - b.id)[0];
  if (!home) return null;
  const ledger = settle(home.state.ledger, at);
  await saveVillageState(client, home.id, { ...home.state, ledger: { ...ledger, amounts: mapResources((kind) => ledger.amounts[kind] + amounts[kind]) } });
  await notifyWorld(client, { worldId: world.id, type: 'village', villageId: home.id });
  return home.id;
}

// Skips the chain: every step and the finale count as done and claimed, and
// what was not yet claimed comes now, a share of it (data/onboarding.json
// `skip`), with a building raised in the player's first village to hold it.
export async function skipOnboarding(client: DbClient, data: GameData, world: World, accountId: number, at: Date): Promise<{ villageId: number | null; reward: Resources; building: string | null }> {
  const member = (await listMembers(client, world.id)).find((m) => m.accountId === accountId);
  if (!member) throw new ForbiddenError('You are not in this world');
  const sum = mapResources(() => 0);
  let any = false;
  for (const def of [...data.onboarding.steps.map((s) => ({ id: s.id as string, reward: s.reward })), { id: 'finale', reward: data.onboarding.finale.reward }]) {
    if (def.id !== 'finale') await markOnboarding(client, world.id, accountId, def.id, at);
    if (!(await markClaimed(client, world.id, accountId, def.id, at))) continue;
    any = true;
    for (const kind of Object.keys(sum) as (keyof Resources)[]) sum[kind] += def.reward[kind];
  }
  if (!any) throw new RuleError('There is nothing left of the tutorial to skip');
  const amounts = mapResources((kind) => Math.floor(sum[kind] * data.onboarding.skip.share));
  // The building first, so the stores are bigger when the reward lands.
  let building: string | null = null;
  const home = (await listVillages(client, world.id)).filter((v) => v.ownerAccountId === accountId && !v.ruin).sort((a, b) => a.id - b.id)[0];
  if (home) {
    const raised = grantBuilding(data, home.state, data.onboarding.skip.building, data.onboarding.skip.level, at, world.speed);
    if (raised) {
      await saveVillageState(client, home.id, raised);
      building = data.onboarding.skip.building;
    }
  }
  const villageId = await reward(client, world, accountId, amounts, at);
  await notifyWorld(client, { worldId: world.id, type: 'world' });
  return { villageId, reward: amounts, building };
}

// Claims a done step's reward; with the last one, the chain's own reward too.
export async function claimOnboarding(client: DbClient, data: GameData, world: World, accountId: number, step: string, at: Date): Promise<{ villageId: number | null; finale: boolean }> {
  const member = (await listMembers(client, world.id)).find((m) => m.accountId === accountId);
  if (!member) throw new ForbiddenError('You are not in this world');
  const def = data.onboarding.steps.find((s) => s.id === step);
  if (!def) throw new RuleError(`Unknown step "${step}"`);
  if (!member.onboarding[step]) throw new RuleError(`"${def.title}" is not done yet`);
  if (!(await markClaimed(client, world.id, accountId, step, at))) throw new RuleError('That reward is already claimed');
  const villageId = await reward(client, world, accountId, def.reward, at);
  const claimed = new Set([...Object.keys(member.onboardingClaimed), step]);
  let finale = false;
  if (data.onboarding.steps.every((s) => claimed.has(s.id)) && (await markClaimed(client, world.id, accountId, 'finale', at))) {
    await reward(client, world, accountId, data.onboarding.finale.reward, at);
    finale = true;
  }
  await notifyWorld(client, { worldId: world.id, type: 'world' });
  return { villageId, finale };
}
