import { loadArmy, saveArmy, type Army } from '../db/armies.js';
import type { StoredRiverEdge } from '../db/rivers.js';
import { authorize } from '../db/delegations.js';
import type { GameData, Stance } from '../data/index.js';
import { notifyWorld } from '../db/notify.js';
import { inTransaction, type Db, type DbClient } from '../db/pool.js';
import { loadVillage, saveVillageState } from '../db/villages.js';
import { getWorld, type World } from '../db/worlds.js';
import { NotFoundError, RuleError } from '../errors.js';
import {
  armyGeneral,
  armyHero,
  circleWagons,
  disbandArmy,
  dispatchArmy,
  mergeArmies,
  moveArmy,
  resupplyArmy,
  sendHome,
  setArmyHome,
  setRespond,
  setReturnHome,
  splitArmy,
  stockStore,
} from '../scheduler/armies.js';
import type { SchedulerDeps } from '../scheduler/events.js';
import { withWorld } from '../scheduler/world.js';
import type { ArmyOrders } from '../sim/armies.js';
import type { Hex } from '../sim/hex.js';
import { loadFort, setFortFloor, type Fort } from '../db/forts.js';
import { buildCrossing, buildFort, buildRoad } from '../scheduler/field.js';
import type { RoadEdge } from '../db/roads.js';
import type { Shipyard } from '../db/shipyards.js';
import { payShipyard } from '../scheduler/mapEvents.js';
import { startRaid, startStrike } from '../scheduler/raids.js';
import type { Front } from '../sim/mapgen.js';

async function worldOfVillage(db: Db, villageId: number): Promise<number> {
  const { rows } = await db.query<{ world_id: number }>('SELECT world_id FROM villages WHERE id = $1', [villageId]);
  if (!rows[0]) throw new NotFoundError(`Village ${villageId} not found`);
  return rows[0].world_id;
}

// Sends troops from the caller's village to another village, or to hold a hex.
export async function sendArmyCommand(
  db: Db,
  deps: SchedulerDeps,
  input: {
    accountId: number;
    villageId: number;
    targetVillageId: number | null;
    target?: Hex | undefined;
    units: Record<string, number>;
    orders: ArmyOrders;
    withHero?: boolean | undefined;
    generalId?: number | undefined;
    stance?: Stance | undefined;
    returnHome?: boolean | undefined;
    now: Date;
  },
): Promise<Army> {
  const worldId = await worldOfVillage(db, input.villageId);
  return withWorld(db, worldId, input.now, deps, async (client, world) => {
    const home = await loadVillage(client, input.villageId);
    await authorize(client, { worldId, ownerAccountId: home.ownerAccountId, actorAccountId: input.accountId, at: input.now, action: 'sent an army', villageId: home.id });
    return dispatchArmy(client, deps.data, world, {
      homeVillageId: home.id,
      targetVillageId: input.targetVillageId,
      targetHex: input.target,
      units: input.units,
      orders: input.orders,
      withHero: input.withHero,
      generalId: input.generalId,
      stance: input.stance,
      returnHome: input.returnHome,
      at: input.now,
    });
  });
}

// Sends troops from the caller's village to raid a front's lands.
export async function raidCommand(
  db: Db,
  deps: SchedulerDeps,
  input: {
    accountId: number;
    villageId: number;
    front: Front;
    depth: number;
    units: Record<string, number>;
    withHero?: boolean | undefined;
    generalId?: number | undefined;
    stance?: Stance | undefined;
    now: Date;
  },
): Promise<Army> {
  const worldId = await worldOfVillage(db, input.villageId);
  return withWorld(db, worldId, input.now, deps, async (client, world) => {
    const home = await loadVillage(client, input.villageId);
    await authorize(client, { worldId, ownerAccountId: home.ownerAccountId, actorAccountId: input.accountId, at: input.now, action: 'sent a raid', villageId: home.id });
    return startRaid(client, deps.data, world, {
      homeVillageId: home.id,
      front: input.front,
      depth: input.depth,
      units: input.units,
      withHero: input.withHero,
      generalId: input.generalId,
      stance: input.stance,
      at: input.now,
    });
  });
}

// Sends troops from the caller's village to strike a horde still gathering
// beyond the map's edge.
export async function strikeCommand(
  db: Db,
  deps: SchedulerDeps,
  input: {
    accountId: number;
    villageId: number;
    waveId: number;
    units: Record<string, number>;
    withHero?: boolean | undefined;
    generalId?: number | undefined;
    stance?: Stance | undefined;
    now: Date;
  },
): Promise<Army> {
  const worldId = await worldOfVillage(db, input.villageId);
  return withWorld(db, worldId, input.now, deps, async (client, world) => {
    const home = await loadVillage(client, input.villageId);
    await authorize(client, { worldId, ownerAccountId: home.ownerAccountId, actorAccountId: input.accountId, at: input.now, action: 'struck a gathering horde', villageId: home.id });
    return startStrike(client, deps.data, world, {
      homeVillageId: home.id,
      waveId: input.waveId,
      units: input.units,
      withHero: input.withHero,
      generalId: input.generalId,
      stance: input.stance,
      at: input.now,
    });
  });
}

// Builds a fort near the caller's village.
export async function buildFortCommand(db: Db, deps: SchedulerDeps, input: { accountId: number; villageId: number; cell: Hex; now: Date }): Promise<Fort> {
  const worldId = await worldOfVillage(db, input.villageId);
  return withWorld(db, worldId, input.now, deps, async (client, world) => {
    const village = await loadVillage(client, input.villageId);
    await authorize(client, { worldId, ownerAccountId: village.ownerAccountId, actorAccountId: input.accountId, at: input.now, action: 'built a fort', villageId: village.id });
    return buildFort(client, deps.data, world, village.id, input.cell, input.now);
  });
}

// Builds a supply point (a grain store for armies) near the caller's village.
export async function buildSupplyPointCommand(db: Db, deps: SchedulerDeps, input: { accountId: number; villageId: number; cell: Hex; now: Date }): Promise<Fort> {
  const worldId = await worldOfVillage(db, input.villageId);
  return withWorld(db, worldId, input.now, deps, async (client, world) => {
    const village = await loadVillage(client, input.villageId);
    await authorize(client, { worldId, ownerAccountId: village.ownerAccountId, actorAccountId: input.accountId, at: input.now, action: 'built a supply point', villageId: village.id });
    return buildFort(client, deps.data, world, village.id, input.cell, input.now, 'supply');
  });
}

// Builds a bridge over a river edge near the caller's village.
export async function buildCrossingCommand(
  db: Db,
  deps: SchedulerDeps,
  input: { accountId: number; villageId: number; a: Hex; b: Hex; now: Date },
): Promise<StoredRiverEdge> {
  const worldId = await worldOfVillage(db, input.villageId);
  return withWorld(db, worldId, input.now, deps, async (client, world) => {
    const village = await loadVillage(client, input.villageId);
    await authorize(client, { worldId, ownerAccountId: village.ownerAccountId, actorAccountId: input.accountId, at: input.now, action: 'built a bridge', villageId: village.id });
    return buildCrossing(client, deps.data, world, village.id, input.a, input.b, input.now);
  });
}

// Builds a road between two neighbouring hexes near the caller's village.
export async function buildRoadCommand(
  db: Db,
  deps: SchedulerDeps,
  input: { accountId: number; villageId: number; a: Hex; b: Hex; now: Date },
): Promise<RoadEdge> {
  const worldId = await worldOfVillage(db, input.villageId);
  return withWorld(db, worldId, input.now, deps, async (client, world) => {
    const village = await loadVillage(client, input.villageId);
    await authorize(client, { worldId, ownerAccountId: village.ownerAccountId, actorAccountId: input.accountId, at: input.now, action: 'built a road', villageId: village.id });
    return buildRoad(client, deps.data, world, village.id, input.a, input.b, input.now);
  });
}

// Sends what a shipyard still needs from the caller's village.
export async function payShipyardCommand(
  db: Db,
  deps: SchedulerDeps,
  input: { accountId: number; villageId: number; shipyardId: number; now: Date },
): Promise<Shipyard> {
  const worldId = await worldOfVillage(db, input.villageId);
  return withWorld(db, worldId, input.now, deps, async (client, world) => {
    const village = await loadVillage(client, input.villageId);
    await authorize(client, { worldId, ownerAccountId: village.ownerAccountId, actorAccountId: input.accountId, at: input.now, action: 'sent resources to a shipyard', villageId: village.id });
    return payShipyard(client, deps.data, world, village.id, input.shipyardId, input.now);
  });
}

// Calls an army standing guard or holding a hex home (not in the middle of a battle).
export async function recallArmyCommand(db: Db, deps: SchedulerDeps, input: { accountId: number; armyId: number; now: Date }): Promise<Army> {
  const { rows } = await db.query<{ world_id: number }>('SELECT world_id FROM armies WHERE id = $1', [input.armyId]);
  if (!rows[0]) throw new NotFoundError('No such army');
  return withWorld(db, rows[0].world_id, input.now, deps, async (client) => {
    const army = await loadArmy(client, input.armyId);
    await authorize(client, {
      worldId: army.worldId,
      ownerAccountId: army.ownerAccountId,
      actorAccountId: input.accountId,
      at: input.now,
      action: 'called an army home',
      villageId: army.homeVillageId,
      refusal: 'Not your army',
    });
    if (army.status === 'engaged') throw new RuleError('That army is in the middle of a battle');
    if (army.status === 'returning') throw new RuleError('They are already on their way home');
    const world = await getWorld(client, army.worldId);
    // One on the march turns for home where it is, into the garrison.
    const back =
      army.status === 'marching'
        ? await moveArmy(client, deps.data, world, army, { villageId: army.homeVillageId }, input.now)
        : army.status === 'stationed'
          ? await sendHome(client, world, army, input.now, deps.data)
          : null;
    if (!back) throw new RuleError('Only armies out in the field can be called home');
    await notifyWorld(client, { worldId: army.worldId, type: 'armies' });
    return back;
  });
}

// A change to one of the caller's armies, with the world locked.
async function armyCommand<T>(
  db: Db,
  deps: SchedulerDeps,
  input: { accountId: number; armyId: number; now: Date },
  action: string,
  apply: (ctx: { client: DbClient; world: World; army: Army }) => Promise<T>,
): Promise<T> {
  const { rows } = await db.query<{ world_id: number }>('SELECT world_id FROM armies WHERE id = $1', [input.armyId]);
  if (!rows[0]) throw new NotFoundError('No such army');
  return withWorld(db, rows[0].world_id, input.now, deps, async (client) => {
    const army = await loadArmy(client, input.armyId);
    await authorize(client, {
      worldId: army.worldId,
      ownerAccountId: army.ownerAccountId,
      actorAccountId: input.accountId,
      at: input.now,
      action,
      villageId: army.homeVillageId,
      refusal: 'Not your army',
    });
    const result = await apply({ client, world: await getWorld(client, army.worldId), army });
    await notifyWorld(client, { worldId: army.worldId, type: 'armies' });
    return result;
  });
}

// Sends a standing army on: to a hex to hold, or into a village.
export async function moveArmyCommand(
  db: Db,
  deps: SchedulerDeps,
  input: { accountId: number; armyId: number; target?: Hex | undefined; villageId?: number | undefined; join?: boolean | undefined; now: Date },
): Promise<Army> {
  return armyCommand(db, deps, input, 'moved an army', ({ client, world, army }) =>
    moveArmy(client, deps.data, world, army, { hex: input.target, villageId: input.villageId, join: input.join }, input.now),
  );
}

// An army's battle stance; not in the middle of a battle.
export async function armyStanceCommand(db: Db, deps: SchedulerDeps, input: { accountId: number; armyId: number; stance: Stance; now: Date }): Promise<Army> {
  return armyCommand(db, deps, input, 'set an army\'s stance', async ({ client, army }) => {
    if (army.status === 'engaged') throw new RuleError('That army is in the middle of a battle');
    if (army.status === 'returning' || army.status === 'done') throw new RuleError('Only armies out in the field take a stance');
    const next = { ...army, stance: input.stance };
    await saveArmy(client, next);
    return next;
  });
}

// Whether an army comes home by itself once its errand is done; one whose
// errand is already done (standing guard, holding a hex) turns home now.
export async function armyReturnHomeCommand(db: Db, deps: SchedulerDeps, input: { accountId: number; armyId: number; returnHome: boolean; now: Date }): Promise<Army> {
  return armyCommand(db, deps, input, 'told an army when to come home', ({ client, world, army }) => setReturnHome(client, deps.data, world, army, input.returnHome, input.now));
}

export async function disbandArmyCommand(db: Db, deps: SchedulerDeps, input: { accountId: number; armyId: number; now: Date }): Promise<Army> {
  return armyCommand(db, deps, input, 'disbanded an army', ({ client, world, army }) => disbandArmy(client, deps.data, world, army, input.now));
}

export async function resupplyArmyCommand(db: Db, deps: SchedulerDeps, input: { accountId: number; armyId: number; now: Date }): Promise<Army> {
  return armyCommand(db, deps, input, 'resupplied an army', ({ client, world, army }) => resupplyArmy(client, deps.data, world, army, input.now));
}

// A standing army on open ground draws its wagons into a wagon fort.
export async function circleWagonsCommand(db: Db, deps: SchedulerDeps, input: { accountId: number; armyId: number; now: Date }): Promise<Army> {
  return armyCommand(db, deps, input, 'circled its wagons', ({ client, world, army }) => circleWagons(client, deps.data, world, army, input.now));
}

// A standing army on a fort or supply point leaves grain in its stores.
export async function stockStoreCommand(db: Db, deps: SchedulerDeps, input: { accountId: number; armyId: number; grain: number; now: Date }): Promise<Army> {
  return armyCommand(db, deps, input, 'left grain in a store', ({ client, world, army }) => stockStore(client, deps.data, world, army, input.grain, input.now));
}

// How low a settlement's grain may fall for armies quartered in it or
// filling up there (null: the default).
export async function setVillageFloorCommand(db: Db, input: { accountId: number; villageId: number; grain: number | null; now: Date }): Promise<void> {
  const worldId = await worldOfVillage(db, input.villageId);
  if (input.grain !== null && !(input.grain >= 0)) throw new RuleError('Say how much grain to keep');
  await inTransaction(db, async (client) => {
    const village = await loadVillage(client, input.villageId);
    await authorize(client, { worldId, ownerAccountId: village.ownerAccountId, actorAccountId: input.accountId, at: input.now, action: 'set the grain kept from armies', villageId: village.id });
    await saveVillageState(client, village.id, { ...village.state, armyFloor: input.grain === null ? null : Math.floor(input.grain) });
    await notifyWorld(client, { worldId, type: 'village', villageId: village.id });
  });
}

// How low a fort's or supply point's grain may fall for armies (null: to the last).
export async function setFortFloorCommand(db: Db, input: { accountId: number; fortId: number; grain: number | null; now: Date }): Promise<Fort> {
  if (input.grain !== null && !(input.grain >= 0)) throw new RuleError('Say how much grain to keep');
  return inTransaction(db, async (client) => {
    const fort = await loadFort(client, input.fortId);
    if (!fort) throw new NotFoundError('No such fort');
    await authorize(client, { worldId: fort.worldId, ownerAccountId: fort.ownerAccountId, actorAccountId: input.accountId, at: input.now, action: 'set the grain kept from armies', ...(fort.villageId !== null ? { villageId: fort.villageId } : {}), refusal: 'Not your fort' });
    const floor = input.grain === null ? null : Math.floor(input.grain);
    await setFortFloor(client, fort.id, floor);
    await notifyWorld(client, { worldId: fort.worldId, type: 'armies' });
    return { ...fort, armyFloor: floor };
  });
}

// An army's home: another of its owner's settlements.
export async function armyHomeCommand(db: Db, deps: SchedulerDeps, input: { accountId: number; armyId: number; villageId: number; now: Date }): Promise<Army> {
  return armyCommand(db, deps, input, 'gave an army a new home', ({ client, world, army }) => setArmyHome(client, world, army, input.villageId));
}

// Whether an army answers battles nearby.
export async function armyRespondCommand(db: Db, deps: SchedulerDeps, input: { accountId: number; armyId: number; respond: boolean; now: Date }): Promise<Army> {
  return armyCommand(db, deps, input, 'told an army whether to answer battles', ({ client, army }) => setRespond(client, army, input.respond));
}

// The hero joins or leaves an army.
export async function armyHeroCommand(db: Db, deps: SchedulerDeps, input: { accountId: number; armyId: number; join: boolean; now: Date }): Promise<Army> {
  return armyCommand(db, deps, input, input.join ? 'put the hero at the head of an army' : 'took the hero from an army', ({ client, world, army }) =>
    armyHero(client, deps.data, world, army, input.join, input.now),
  );
}

// A general takes command of an army, or the one leading it leaves (null).
export async function armyGeneralCommand(db: Db, deps: SchedulerDeps, input: { accountId: number; armyId: number; generalId: number | null; now: Date }): Promise<Army> {
  return armyCommand(db, deps, input, 'changed the general of an army', ({ client, world, army }) => armyGeneral(client, deps.data, world, army, input.generalId, input.now));
}

// Another standing army joins this one.
export async function mergeArmiesCommand(db: Db, deps: SchedulerDeps, input: { accountId: number; armyId: number; otherId: number; now: Date }): Promise<Army> {
  return armyCommand(db, deps, input, 'merged two armies', ({ client, world, army }) => mergeArmies(client, deps.data, world, army, input.otherId, input.now));
}

// Some of a standing army's troops become an army of their own.
export async function splitArmyCommand(
  db: Db,
  deps: SchedulerDeps,
  input: { accountId: number; armyId: number; units: Record<string, number>; withHero?: boolean | undefined; withGeneral?: boolean | undefined; now: Date },
): Promise<{ army: Army; split: Army }> {
  return armyCommand(db, deps, input, 'split an army', ({ client, world, army }) =>
    splitArmy(client, deps.data, world, army, { units: input.units, withHero: input.withHero, withGeneral: input.withGeneral }, input.now),
  );
}
