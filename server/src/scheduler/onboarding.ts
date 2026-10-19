// The getting-started chain (data/onboarding.json): the first time a player
// does each step, it is marked done and its reward goes to their first village.
import type { GameData, OnboardingStep } from '../data/index.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { listVillages, saveVillageState } from '../db/villages.js';
import { markOnboarding, type World } from '../db/worlds.js';
import { receive } from '../sim/logistics.js';
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
  const home = (await listVillages(client, world.id)).filter((v) => v.ownerAccountId === accountId && !v.ruin).sort((a, b) => a.id - b.id)[0];
  if (home) {
    await saveVillageState(client, home.id, { ...home.state, ledger: receive(home.state.ledger, at, def.reward).ledger });
    await notifyWorld(client, { worldId: world.id, type: 'village', villageId: home.id });
  }
  await tell(client, world, accountId, { kind: 'onboarding', tier: 'digest', title: `Done: ${def.title}`, body: `A reward has reached ${home?.name ?? 'your village'}.` }, at);
  await notifyWorld(client, { worldId: world.id, type: 'world' });
}
