import { deleteGeneral, insertGeneral, listGenerals, loadGeneral, saveGeneral, type General } from '../db/generals.js';
import { loadLand } from '../db/rivers.js';
import { notifyWorld } from '../db/notify.js';
import type { Db, DbClient } from '../db/pool.js';
import { listVillages, loadVillage, type Village } from '../db/villages.js';
import { getWorld } from '../db/worlds.js';
import { RuleError } from '../errors.js';
import { scheduleEvent, type SchedulerDeps } from '../scheduler/events.js';
import type { GeneralPayload } from '../scheduler/generals.js';
import { withWorld } from '../scheduler/world.js';
import { checkRecruit, generalName, recruitCost, recruitMs } from '../sim/generals.js';
import { hex } from '../sim/hex.js';
import { roadRoute } from '../sim/logistics.js';
import { spend } from '../sim/resources.js';
import { ownVillageCommand, type VillageCommandInput } from './village.js';

// Recruits a general at the caller's village, paid from its stores.
export async function recruitGeneralCommand(db: Db, deps: SchedulerDeps, input: VillageCommandInput): Promise<{ village: Village; general: General }> {
  const { village, result } = await ownVillageCommand(db, deps, { ...input, action: 'recruited a general' }, async ({ client, world, village }) => {
    const owner = village.ownerAccountId!;
    const owned = (await listGenerals(client, world.id, owner)).length;
    const halls = (await listVillages(client, world.id)).filter((v) => v.ownerAccountId === owner).map((v) => v.state.levels.heroes_hall ?? 0);
    checkRecruit(deps.data, { hallLevel: village.state.levels.heroes_hall ?? 0, hallLevels: halls, owned });
    const ledger = spend(village.state.ledger, input.now, recruitCost(deps.data, owned));
    const until = new Date(input.now.getTime() + recruitMs(deps.data, world.speed));
    const general = await insertGeneral(client, {
      worldId: world.id,
      accountId: owner,
      status: 'recruiting',
      villageId: village.id,
      until,
      name: (id) => generalName(deps.data, id),
    });
    await scheduleEvent(client, world.id, until, 'general_ready', { generalId: general.id } satisfies GeneralPayload);
    await notifyWorld(client, { worldId: world.id, type: 'generals' });
    return { state: { ...village.state, ledger }, result: general };
  });
  return { village, general: result };
}

// A change to one of the caller's generals, with the world locked.
async function generalCommand(
  db: Db,
  deps: SchedulerDeps,
  input: { accountId: number; generalId: number; now: Date },
  apply: (general: General, worldId: number, client: DbClient) => Promise<General | null>,
): Promise<General | null> {
  const { rows } = await db.query<{ world_id: number }>('SELECT world_id FROM generals WHERE id = $1', [input.generalId]);
  if (!rows[0]) throw new RuleError('No such general');
  const worldId = Number(rows[0].world_id);
  return withWorld(db, worldId, input.now, deps, async (client) => {
    const general = await loadGeneral(client, input.generalId);
    if (general.accountId !== input.accountId) throw new RuleError('That general is not yours');
    const next = await apply(general, worldId, client);
    await notifyWorld(client, { worldId, type: 'generals' });
    return next;
  });
}

function ready(general: General): void {
  if (general.status === 'recruiting') throw new RuleError(`${general.name} has not arrived yet`);
  if (general.status === 'traveling') throw new RuleError(`${general.name} is already on the road`);
  if (general.status === 'with_army') throw new RuleError(`${general.name} is leading an army`);
}

// Sends a general to another of the caller's villages, to command its garrison.
export async function moveGeneralCommand(
  db: Db,
  deps: SchedulerDeps,
  input: { accountId: number; generalId: number; villageId: number; now: Date },
): Promise<General> {
  return (await generalCommand(db, deps, input, async (general, worldId, client) => {
    ready(general);
    if (general.villageId === input.villageId) throw new RuleError(`${general.name} is already there`);
    const world = await getWorld(client, worldId);
    const destination = await loadVillage(client, input.villageId).catch(() => null);
    if (!destination || destination.worldId !== worldId || destination.ownerAccountId !== input.accountId) {
      throw new RuleError('Generals only travel between your own villages');
    }
    const from = await loadVillage(client, general.villageId!);
    if (from.state.besieged) throw new RuleError(`${general.name} won't leave ${from.name} in the middle of a battle`);
    const path = roadRoute(deps.data, await loadLand(client, worldId), hex(from.q, from.r), hex(destination.q, destination.r), deps.data.heroes.generals.speed, world.speed);
    const until = new Date(input.now.getTime() + path.at(-1)!.atMs);
    const next: General = { ...general, status: 'traveling', villageId: destination.id, path, departsAt: input.now, until };
    await saveGeneral(client, next);
    await scheduleEvent(client, worldId, until, 'general_arrive', { generalId: general.id } satisfies GeneralPayload);
    return next;
  }))!;
}

// Sends a general away for good.
export async function dismissGeneralCommand(db: Db, deps: SchedulerDeps, input: { accountId: number; generalId: number; now: Date }): Promise<void> {
  await generalCommand(db, deps, input, async (general, _worldId, client) => {
    if (general.status === 'with_army') throw new RuleError(`${general.name} is leading an army; call it home first`);
    await deleteGeneral(client, general.id);
    return null;
  });
}
