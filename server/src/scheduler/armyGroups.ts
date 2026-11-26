// Army groups on the scheduler (data/armies.json groups): every few game
// minutes (group_check) a group has what it lacks trained, each unit in the
// owner's settlement closest to its army (to its home while it has none),
// and the troops march to the army once trained (or, with none standing
// yet, gather at the home as its army). The rules: sim/armyGroups.ts.
import { z } from 'zod';
import type { GameData } from '../data/index.js';
import { insertArmy, listArmies, loadArmy, saveArmy, type Army } from '../db/armies.js';
import { findArmyGroup, saveArmyGroup, setArmyGroupTag, type ArmyGroup } from '../db/armyGroups.js';
import { countVillagesOwned } from '../db/expeditions.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { listVillages, loadVillage, saveVillageState, type Village } from '../db/villages.js';
import { addBought, boughtCount, type World } from '../db/worlds.js';
import { RuleError } from '../errors.js';
import { addUnits, total } from '../sim/armies.js';
import { batchTries, missingUnits } from '../sim/armyGroups.js';
import { hex, hexDistance, type Hex } from '../sim/hex.js';
import { InsufficientResourcesError, spend } from '../sim/resources.js';
import { fullSupply } from '../sim/supply.js';
import { batchCompletesAt, type TrainingBatch, type Units } from '../sim/training.js';
import { leaveGarrison, queueTraining } from '../sim/village.js';
import { dispatchArmy, mergeArmies, moveArmy, placeOf, planHunger, quarter, villageSpare } from './armies.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';
import { armySlotsOf } from './slots.js';

export const groupCheckPayload = z.object({ groupId: z.number().int() });
export type GroupCheckPayload = z.infer<typeof groupCheckPayload>;

function checkMs(data: GameData, worldSpeed: number): number {
  return Math.round((data.armies.groups.checkMinutes * 60_000) / worldSpeed);
}

export async function scheduleGroupCheck(client: DbClient, data: GameData, world: World, groupId: number, from: Date): Promise<void> {
  await scheduleEvent(client, world.id, new Date(from.getTime() + checkMs(data, world.speed)), 'group_check', { groupId } satisfies GroupCheckPayload);
}

// The group's army while it stands (null: none, or lost).
export async function fieldedArmy(client: DbClient, group: ArmyGroup): Promise<Army | null> {
  if (group.armyId === null) return null;
  const army = await loadArmy(client, group.armyId).catch(() => null);
  return army && army.status !== 'done' && army.ownerAccountId === group.ownerAccountId ? army : null;
}

function ownSettlements(villages: readonly Village[], owner: number): Village[] {
  return villages.filter((v) => v.ownerAccountId === owner && !v.ruin);
}

// Troops already on their way to the group: in training for it, and
// marching to join it.
async function comingTo(client: DbClient, world: World, group: ArmyGroup, villages: readonly Village[]): Promise<Units> {
  let coming: Units = {};
  for (const v of villages) {
    for (const batch of v.state.training) if (batch.group === group.id) coming = addUnits(coming, { [batch.unit]: batch.size ?? batch.count });
  }
  for (const a of await listArmies(client, world.id)) {
    if (a.groupId === group.id && a.status !== 'done' && a.id !== group.armyId) coming = addUnits(coming, a.units);
  }
  return coming;
}

// Where the group recruits for: its home while it has no army (if the home
// stands), its army while that stands in one of its owner's settlements,
// forts or supply points; null: not now.
async function recruitPoint(client: DbClient, group: ArmyGroup, army: Army | null): Promise<Hex | null> {
  if (!army) {
    const home = await loadVillage(client, group.homeVillageId).catch(() => null);
    return home && !home.ruin && home.ownerAccountId === group.ownerAccountId ? hex(home.q, home.r) : null;
  }
  if (army.status !== 'stationed') return null;
  const place = await placeOf(client, army);
  if (!place) return null;
  const owner = place.kind === 'village' ? place.village.ownerAccountId : place.fort.ownerAccountId;
  return owner === group.ownerAccountId ? hex(army.targetQ, army.targetR) : null;
}

// Has what the group lacks trained: for each unit (in name order) a batch
// in the owner's closest settlement that can train it and pay for as many
// as possible at once (as many as are missing, or half, a quarter... down
// to one), within the owner's army slots.
export async function recruitGroup(client: DbClient, data: GameData, world: World, group: ArmyGroup, at: Date): Promise<void> {
  const army = await fieldedArmy(client, group);
  const point = await recruitPoint(client, group, army);
  if (!point) return;
  const villages = ownSettlements(await listVillages(client, world.id), group.ownerAccountId);
  const missing = missingUnits(group.composition, army?.units ?? {}, await comingTo(client, world, group, villages));
  const near = [...villages].sort((a, b) => hexDistance(point, hex(a.q, a.r)) - hexDistance(point, hex(b.q, b.r)) || a.id - b.id);
  const owned = await countVillagesOwned(client, world.id, group.ownerAccountId);
  for (const [unit, n] of Object.entries(missing)) {
    const def = data.units.units[unit];
    if (!def) continue;
    const slots = await armySlotsOf(client, data, world.id, group.ownerAccountId);
    const fit = def.slots > 0 ? Math.floor((slots.cap - slots.used) / def.slots) : n;
    const most = Math.min(n, fit);
    if (most < 1) continue;
    const tries = def.oneAtATime ? [1] : batchTries(most, data.units.maxBatch);
    const bought = await boughtCount(client, world.id, group.ownerAccountId, unit);
    queued: for (const v of near) {
      const village = await loadVillage(client, v.id);
      if (village.state.besieged) continue;
      for (const count of tries) {
        let step: ReturnType<typeof queueTraining>;
        try {
          step = queueTraining(data, village.state, unit, count, at, world.speed, owned, bought);
        } catch (error) {
          if (error instanceof InsufficientResourcesError) continue;
          if (error instanceof RuleError) continue queued;
          throw error;
        }
        const batch: TrainingBatch = { ...step.batch, group: group.id };
        const state = { ...step.state, training: [...step.state.training.slice(0, -1), batch] };
        await saveVillageState(client, village.id, state);
        if (def.costStep) await addBought(client, world.id, group.ownerAccountId, unit, count);
        await scheduleEvent(client, world.id, batchCompletesAt(batch), 'training_complete', { villageId: village.id });
        await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
        break queued;
      }
    }
  }
}

// Troops at home in `village` become an army standing there (quartered in
// it), with what grain they carry from its granary.
async function standHere(client: DbClient, data: GameData, world: World, village: Village, units: Units, at: Date): Promise<Army> {
  let state = leaveGarrison(data, village.state, units, at, world.speed);
  const grain = Math.min(fullSupply(data, units), villageSpare(data, state, at));
  if (grain > 0) state = { ...state, ledger: spend(state.ledger, at, { wood: 0, stone: 0, grain, iron: 0 }) };
  await saveVillageState(client, village.id, state);
  const army = await insertArmy(client, {
    worldId: world.id,
    ownerAccountId: village.ownerAccountId,
    homeVillageId: village.id,
    targetVillageId: village.id,
    targetQ: village.q,
    targetR: village.r,
    heroAccountId: null,
    orders: 'support',
    stance: village.state.stance,
    units,
    supply: grain,
    supplyAt: at,
    path: [{ q: village.q, r: village.r, atMs: 0 }],
    departsAt: at,
    arrivesAt: at,
  });
  const stationed = await quarter(client, data, world, { ...army, status: 'stationed' }, at);
  await saveArmy(client, stationed);
  await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
  return planHunger(client, data, world, stationed, at);
}

// Trained troops of the group's in `village` go to it: they join its army
// standing there, march to where it stands or goes, or, with no army yet,
// gather at the group's home (as its army, once there).
async function sendToGroup(client: DbClient, data: GameData, world: World, group: ArmyGroup, village: Village, units: Units, at: Date): Promise<void> {
  const army = await fieldedArmy(client, group);
  if (!army && village.id === group.homeVillageId) {
    const formed = await standHere(client, data, world, village, units, at);
    await saveArmyGroup(client, { ...group, armyId: formed.id });
    return;
  }
  if (army && army.targetVillageId === village.id) {
    const here = await standHere(client, data, world, village, units, at);
    if (army.status === 'stationed') await mergeArmies(client, data, world, army, here.id, at);
    else await setArmyGroupTag(client, here.id, group.id);
    return;
  }
  const to = army
    ? army.targetVillageId !== null
      ? { targetVillageId: army.targetVillageId, orders: 'support' as const }
      : { targetVillageId: null, targetHex: hex(army.targetQ, army.targetR), orders: 'hold' as const }
    : { targetVillageId: group.homeVillageId, orders: 'support' as const };
  const sent = await dispatchArmy(client, data, world, { homeVillageId: village.id, units, at, ...to });
  await setArmyGroupTag(client, sent.id, group.id);
}

// Training done in a village: each group's batches among them (`batches`,
// as they stood before settling) send as many of their unit as stand at
// home, up to their size, to the group. Under siege, they stay.
export async function groupTrained(client: DbClient, data: GameData, world: World, villageId: number, batches: readonly TrainingBatch[], at: Date): Promise<void> {
  const byGroup = new Map<number, Units>();
  let village = await loadVillage(client, villageId);
  if (village.state.besieged) return;
  const taken: Record<string, number> = {};
  for (const batch of batches) {
    if (batch.group === undefined) continue;
    const n = Math.min((village.state.garrison[batch.unit] ?? 0) - (taken[batch.unit] ?? 0), batch.size ?? batch.count);
    if (n <= 0) continue;
    taken[batch.unit] = (taken[batch.unit] ?? 0) + n;
    byGroup.set(batch.group, addUnits(byGroup.get(batch.group) ?? {}, { [batch.unit]: n }));
  }
  for (const [groupId, units] of [...byGroup.entries()].sort((a, b) => a[0] - b[0])) {
    const group = await findArmyGroup(client, groupId);
    if (!group || group.ownerAccountId !== village.ownerAccountId) continue;
    village = await loadVillage(client, villageId);
    await client.query('SAVEPOINT group_trained');
    try {
      await sendToGroup(client, data, world, group, village, units, at);
      await client.query('RELEASE SAVEPOINT group_trained');
    } catch (error) {
      await client.query('ROLLBACK TO SAVEPOINT group_trained');
      if (!(error instanceof RuleError)) throw error;
    }
  }
  await notifyWorld(client, { worldId: world.id, type: 'armies' });
}

// An army of the group's, standing somewhere, joins it: it merges into the
// group's army standing on the same hex, marches on to it if it stands or
// goes elsewhere, or becomes the group's army if it has none. One in a
// battle, or coming home, waits.
export async function joinGroup(client: DbClient, data: GameData, world: World, reinforcement: Army, at: Date): Promise<void> {
  if (reinforcement.groupId === null || reinforcement.status !== 'stationed') return;
  const group = await findArmyGroup(client, reinforcement.groupId);
  if (!group) {
    await setArmyGroupTag(client, reinforcement.id, null);
    return;
  }
  const army = await fieldedArmy(client, group);
  if (!army || army.id === reinforcement.id) {
    await saveArmyGroup(client, { ...group, armyId: reinforcement.id });
    await setArmyGroupTag(client, reinforcement.id, null);
    return;
  }
  const sameHex = army.targetQ === reinforcement.targetQ && army.targetR === reinforcement.targetR;
  if (army.status === 'stationed' && sameHex) {
    await mergeArmies(client, data, world, army, reinforcement.id, at);
    await setArmyGroupTag(client, reinforcement.id, null);
    return;
  }
  if ((army.status !== 'stationed' && army.status !== 'marching') || sameHex) return;
  const to = army.targetVillageId !== null ? { villageId: army.targetVillageId, join: false } : { hex: hex(army.targetQ, army.targetR) };
  await client.query('SAVEPOINT join_group');
  try {
    await moveArmy(client, data, world, reinforcement, to, at);
    await client.query('RELEASE SAVEPOINT join_group');
  } catch (error) {
    await client.query('ROLLBACK TO SAVEPOINT join_group');
    if (!(error instanceof RuleError)) throw error;
  }
}

// A group's turn: its armies standing on their way join it, then what it
// lacks is recruited.
export async function runGroup(client: DbClient, data: GameData, world: World, group: ArmyGroup, at: Date): Promise<void> {
  for (const a of await listArmies(client, world.id)) {
    if (a.groupId !== group.id || a.status !== 'stationed') continue;
    await joinGroup(client, data, world, a, at);
    const fresh = await findArmyGroup(client, group.id);
    if (fresh) group = fresh;
  }
  await recruitGroup(client, data, world, group, at);
  await notifyWorld(client, { worldId: world.id, type: 'armies' });
}

export const groupHandlers: HandlerRegistry = {
  async group_check({ client, data, world }, event) {
    const { groupId } = groupCheckPayload.parse(event.payload);
    const group = await findArmyGroup(client, groupId);
    if (!group) return;
    await runGroup(client, data, world, group, event.dueAt);
    await scheduleGroupCheck(client, data, world, groupId, event.dueAt);
  },
};

// The total of a group's composition (for limits).
export function groupSize(group: Pick<ArmyGroup, 'composition'>): number {
  return total(group.composition);
}
