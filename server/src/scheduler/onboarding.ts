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
async function reward(client: DbClient, world: World, accountId: number, amounts: Resources, at: Date): Promise<number | null> {
  const home = (await listVillages(client, world.id)).filter((v) => v.ownerAccountId === accountId && !v.ruin).sort((a, b) => a.id - b.id)[0];
  if (!home) return null;
  const ledger = settle(home.state.ledger, at);
  await saveVillageState(client, home.id, { ...home.state, ledger: { ...ledger, amounts: mapResources((kind) => ledger.amounts[kind] + amounts[kind]) } });
  await notifyWorld(client, { worldId: world.id, type: 'village', villageId: home.id });
  return home.id;
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
