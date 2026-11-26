// Army groups (data/armies.json groups; scheduler/armyGroups.ts): a named
// army with a set composition, raised and kept up by itself.
import { deleteArmyGroup, findArmyGroup, insertArmyGroup, listArmyGroups, saveArmyGroup, type ArmyGroup } from '../db/armyGroups.js';
import { authorize } from '../db/delegations.js';
import { notifyWorld } from '../db/notify.js';
import type { Db, DbClient } from '../db/pool.js';
import { loadVillage, type Village } from '../db/villages.js';
import type { World } from '../db/worlds.js';
import { NotFoundError, RuleError } from '../errors.js';
import { recruitGroup, scheduleGroupCheck } from '../scheduler/armyGroups.js';
import type { SchedulerDeps } from '../scheduler/events.js';
import { withWorld } from '../scheduler/world.js';
import { groupName, validateComposition } from '../sim/armyGroups.js';

async function worldOfVillage(db: Db, villageId: number): Promise<number> {
  const { rows } = await db.query<{ world_id: number }>('SELECT world_id FROM villages WHERE id = $1', [villageId]);
  if (!rows[0]) throw new NotFoundError(`Village ${villageId} not found`);
  return Number(rows[0].world_id);
}

async function worldOfGroup(db: Db, groupId: number): Promise<number> {
  const { rows } = await db.query<{ world_id: number }>('SELECT world_id FROM army_groups WHERE id = $1', [groupId]);
  if (!rows[0]) throw new NotFoundError(`Army group ${groupId} not found`);
  return Number(rows[0].world_id);
}

// A home for a group: one of the owner's own standing settlements.
async function homeOf(client: DbClient, world: World, villageId: number, owner: number | null): Promise<Village> {
  const village = await loadVillage(client, villageId).catch(() => null);
  if (!village || village.worldId !== world.id || village.ownerAccountId === null || (owner !== null && village.ownerAccountId !== owner) || village.ruin) {
    throw new RuleError('Only one of your own settlements can be its home');
  }
  return village;
}

// A new group: its troops are recruited at once, and then every few game
// minutes until it is whole.
export async function createArmyGroupCommand(
  db: Db,
  deps: SchedulerDeps,
  input: { accountId: number; worldId: number; homeVillageId: number; name?: string | undefined; composition: Record<string, number>; now: Date },
): Promise<ArmyGroup> {
  const worldId = await worldOfVillage(db, input.homeVillageId);
  if (worldId !== input.worldId) throw new RuleError('Only one of your own settlements can be its home');
  return withWorld(db, worldId, input.now, deps, async (client, world) => {
    const home = await homeOf(client, world, input.homeVillageId, null);
    const owner = home.ownerAccountId!;
    await authorize(client, { worldId, ownerAccountId: owner, actorAccountId: input.accountId, at: input.now, action: 'raised an army group', villageId: home.id });
    const most = deps.data.armies.groups.maxPerPlayer;
    if ((await listArmyGroups(client, worldId, owner)).length >= most) throw new RuleError(`You keep at most ${most} army groups`);
    const composition = validateComposition(deps.data, input.composition);
    const group = await insertArmyGroup(client, { worldId, ownerAccountId: owner, name: groupName(input.name, home.name), composition, homeVillageId: home.id, createdAt: input.now });
    await recruitGroup(client, deps.data, world, group, input.now);
    await scheduleGroupCheck(client, deps.data, world, group.id, input.now);
    await notifyWorld(client, { worldId, type: 'armies' });
    return (await findArmyGroup(client, group.id))!;
  });
}

// Renames a group, gives it another home or another composition.
export async function updateArmyGroupCommand(
  db: Db,
  deps: SchedulerDeps,
  input: { accountId: number; groupId: number; name?: string | undefined; homeVillageId?: number | undefined; composition?: Record<string, number> | undefined; now: Date },
): Promise<ArmyGroup> {
  const worldId = await worldOfGroup(db, input.groupId);
  return withWorld(db, worldId, input.now, deps, async (client, world) => {
    const group = (await findArmyGroup(client, input.groupId))!;
    await authorize(client, { worldId, ownerAccountId: group.ownerAccountId, actorAccountId: input.accountId, at: input.now, action: 'changed an army group', villageId: group.homeVillageId });
    const home = input.homeVillageId === undefined ? null : await homeOf(client, world, input.homeVillageId, group.ownerAccountId);
    const next: ArmyGroup = {
      ...group,
      name: input.name === undefined ? group.name : groupName(input.name, (home ?? (await loadVillage(client, group.homeVillageId))).name),
      homeVillageId: home?.id ?? group.homeVillageId,
      composition: input.composition === undefined ? group.composition : validateComposition(deps.data, input.composition),
    };
    await saveArmyGroup(client, next);
    await notifyWorld(client, { worldId, type: 'armies' });
    return next;
  });
}

// A group given up: its army stays an army, its troops on the way stand
// where they arrive, and those in training join their garrison.
export async function disbandArmyGroupCommand(db: Db, deps: SchedulerDeps, input: { accountId: number; groupId: number; now: Date }): Promise<void> {
  const worldId = await worldOfGroup(db, input.groupId);
  await withWorld(db, worldId, input.now, deps, async (client) => {
    const group = (await findArmyGroup(client, input.groupId))!;
    await authorize(client, { worldId, ownerAccountId: group.ownerAccountId, actorAccountId: input.accountId, at: input.now, action: 'disbanded an army group', villageId: group.homeVillageId });
    await deleteArmyGroup(client, group.id);
    await notifyWorld(client, { worldId, type: 'armies' });
  });
}
