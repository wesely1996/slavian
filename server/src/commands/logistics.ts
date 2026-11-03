import type { GameData, TerrainId } from '../data/index.js';
import { loadLand } from '../db/rivers.js';
import { caravansOut, insertCaravan, loadCaravan, saveCaravanRoute, type Caravan } from '../db/caravans.js';
import { effectiveBonuses } from '../db/heroes.js';
import { notifyWorld } from '../db/notify.js';
import type { Db, DbClient } from '../db/pool.js';
import { loadFort } from '../db/forts.js';
import { loadVault, saveVault, type Vault } from '../db/vaults.js';
import { loadVillage, type Village } from '../db/villages.js';
import { loadHexes, type World } from '../db/worlds.js';
import { NotFoundError, RuleError } from '../errors.js';
import { scheduleEvent, type SchedulerDeps } from '../scheduler/events.js';
import type { CaravanPayload } from '../scheduler/caravans.js';
import { planAmbushes } from '../scheduler/camps.js';
import { fighters } from '../sim/armies.js';
import { withWorld } from '../scheduler/world.js';
import { hex, type Hex } from '../sim/hex.js';
import {
  CARAVAN_YARD,
  caravanRoute,
  caravansAt,
  caravansFor,
  HOLY_CITY,
  spliceRoute,
  vaultUpgradeCost,
  vaultUpgradeMs,
  withdraw,
} from '../sim/logistics.js';
import { RESOURCE_KINDS, spend, type Resources } from '../sim/resources.js';
import { sendAway, type VillageState } from '../sim/village.js';
import { ownVillageCommand, type VillageCommandInput } from './village.js';

// Where a caravan goes: an allied village, or the vault when null (or, on
// a supply route, a fort or supply point).
export interface CaravanOrder {
  destinationVillageId: number | null;
  destinationFortId?: number | undefined;
  load: Resources;
  // Troops guarding it against camps on the road.
  escort?: Record<string, number> | undefined;
}

// Sends the escort away with the caravan (they come back with it).
function withEscort(data: GameData, state: VillageState, escort: Record<string, number> | undefined, at: Date, worldSpeed: number): VillageState {
  let next = state;
  for (const [unit, n] of Object.entries(escort ?? {})) {
    if (n <= 0) continue;
    if (!fighters(data, { [unit]: 1 })[unit]) throw new RuleError(`${data.units.units[unit]?.name ?? unit} can't guard caravans`);
    next = sendAway(data, next, unit, n, at, worldSpeed);
  }
  return next;
}

export async function dispatchCaravan(
  client: DbClient,
  data: GameData,
  world: World,
  village: Village,
  kind: Caravan['kind'],
  order: CaravanOrder,
  now: Date,
): Promise<Caravan> {
  const yard = village.state.levels[CARAVAN_YARD] ?? 0;
  if (yard < 1) throw new RuleError('Build a Caravan Yard first');
  const bonuses = await effectiveBonuses(client, data, village);
  const needed = caravansFor(data, order.load, bonuses);
  const free = caravansAt(data, yard) - (await caravansOut(client, village.id));
  if (needed > free) {
    throw new RuleError(`That takes ${needed} caravan${needed === 1 ? '' : 's'}; ${Math.max(0, free)} at home`);
  }

  let to: Hex = HOLY_CITY;
  if (order.destinationFortId !== undefined) {
    const fort = await loadFort(client, order.destinationFortId);
    if (!fort || fort.worldId !== world.id) throw new NotFoundError('No such fort or supply point');
    to = hex(fort.q, fort.r);
  } else if (order.destinationVillageId !== null) {
    if (order.destinationVillageId === village.id) throw new RuleError('Send it to another village');
    const destination = await loadVillage(client, order.destinationVillageId).catch(() => null);
    if (!destination || destination.worldId !== world.id) throw new NotFoundError('No such village in this world');
    to = hex(destination.q, destination.r);
  }
  const terrain = await loadLand(client, world.id);
  const path = caravanRoute(data, terrain, hex(village.q, village.r), to, world.speed, bonuses);
  const travelMs = path.at(-1)!.atMs;
  const arrivesAt = new Date(now.getTime() + travelMs);
  const caravan = await insertCaravan(client, {
    worldId: world.id,
    villageId: village.id,
    destinationVillageId: order.destinationVillageId,
    destinationFortId: order.destinationFortId ?? null,
    kind,
    caravans: needed,
    cargo: order.load,
    path,
    departsAt: now,
    arrivesAt,
    returnsAt: new Date(arrivesAt.getTime() + travelMs),
    escort: Object.fromEntries(Object.entries(order.escort ?? {}).filter(([, n]) => n > 0)),
  });
  const payload: CaravanPayload = { caravanId: caravan.id };
  await scheduleEvent(client, world.id, arrivesAt, 'caravan_arrive', payload);
  await planAmbushes(client, data, world, caravan, 'out', now);
  await notifyWorld(client, { worldId: world.id, type: 'caravans' });
  return caravan;
}

// Where a caravan on its way out is turned: home, or (one carrying goods
// out, not on a supply route) another village or the vault (null).
export type CaravanTurn = { home: true } | { villageId: number | null };

// Turns a caravan on its way out: it finishes the hex it is crossing, then
// comes home along the road it took with its goods, or takes a new road to
// another village or the vault. The road behind it stays, so the way home
// still runs back along it. Ambushes on its road are planned anew.
export async function rerouteCaravanCommand(
  db: Db,
  deps: SchedulerDeps,
  input: { accountId: number; caravanId: number; turn: CaravanTurn; now: Date },
): Promise<Caravan> {
  const { rows } = await db.query<{ village_id: number }>('SELECT village_id FROM caravans WHERE id = $1', [input.caravanId]);
  if (!rows[0]) throw new NotFoundError('No such caravan');
  const { result } = await ownVillageCommand(
    db,
    deps,
    { accountId: input.accountId, villageId: rows[0].village_id, now: input.now, action: 'turned a caravan' },
    async ({ client, world, village }) => {
      const caravan = await loadCaravan(client, input.caravanId);
      if (caravan.status !== 'outbound') throw new RuleError('Only caravans on their way out can be turned');
      const elapsed = input.now.getTime() - caravan.departsAt.getTime();
      let turned: Caravan;
      if ('home' in input.turn) {
        // It goes back from the hex it is crossing, with what it took out
        // (a caravan fetching from the vault carries nothing yet).
        const path = spliceRoute(caravan.path, elapsed, (from) => [{ ...from, atMs: 0 }]);
        const there = path.at(-1)!.atMs;
        turned = {
          ...caravan,
          path,
          status: 'returning',
          carriedBack: caravan.kind === 'deliver' ? caravan.cargo : { wood: 0, stone: 0, grain: 0, iron: 0 },
          arrivesAt: new Date(caravan.departsAt.getTime() + there),
          returnsAt: new Date(caravan.departsAt.getTime() + 2 * there),
        };
      } else {
        if (caravan.kind !== 'deliver' || caravan.destinationFortId !== null) throw new RuleError('This caravan can only be turned back');
        const to = input.turn.villageId;
        if (to === caravan.destinationVillageId) throw new RuleError('It is already on its way there');
        let dest: Hex = HOLY_CITY;
        if (to !== null) {
          if (to === village.id) throw new RuleError('Turn it back to bring it home');
          const destination = await loadVillage(client, to).catch(() => null);
          if (!destination || destination.worldId !== world.id) throw new NotFoundError('No such village in this world');
          dest = hex(destination.q, destination.r);
        }
        const bonuses = await effectiveBonuses(client, deps.data, village);
        const land = await loadLand(client, world.id);
        const path = spliceRoute(caravan.path, elapsed, (from) => caravanRoute(deps.data, land, from, dest, world.speed, bonuses));
        const travel = path.at(-1)!.atMs;
        turned = {
          ...caravan,
          path,
          destinationVillageId: to,
          arrivesAt: new Date(caravan.departsAt.getTime() + travel),
          returnsAt: new Date(caravan.departsAt.getTime() + 2 * travel),
        };
      }
      await saveCaravanRoute(client, turned);
      // Camps lying in wait on the old road wait in vain.
      await client.query(
        `UPDATE scheduled_events SET status = 'done', processed_at = now(), error = 'superseded'
         WHERE world_id = $1 AND status = 'pending' AND type = 'caravan_ambush' AND payload @> $2::jsonb`,
        [world.id, JSON.stringify({ caravanId: caravan.id })],
      );
      const payload: CaravanPayload = { caravanId: caravan.id };
      if (turned.status === 'returning') {
        await scheduleEvent(client, world.id, turned.returnsAt, 'caravan_return', payload);
        await planAmbushes(client, deps.data, world, turned, 'back', input.now);
      } else {
        await scheduleEvent(client, world.id, turned.arrivesAt, 'caravan_arrive', payload);
        await planAmbushes(client, deps.data, world, turned, 'out', input.now);
      }
      await notifyWorld(client, { worldId: world.id, type: 'caravans' });
      return { state: village.state, result: turned };
    },
  );
  return result;
}

// Loads resources from the caravan's village and sends them to an ally or
// the Holy City vault.
export async function sendCaravanCommand(
  db: Db,
  deps: SchedulerDeps,
  input: VillageCommandInput & CaravanOrder,
): Promise<{ village: Village; caravan: Caravan }> {
  const { village, result } = await ownVillageCommand(db, deps, { ...input, action: 'sent a caravan' }, async ({ client, world, village }) => {
    const escorted = withEscort(deps.data, village.state, input.escort, input.now, world.speed);
    const caravan = await dispatchCaravan(client, deps.data, world, village, 'deliver', input, input.now);
    const state: VillageState = { ...escorted, ledger: spend(escorted.ledger, input.now, input.load) };
    // A gift: to the vault or a teammate's village, not one's own.
    const destination = input.destinationVillageId === null ? null : await loadVillage(client, input.destinationVillageId);
    const gift = destination === null || destination.ownerAccountId !== village.ownerAccountId;
    return { state, result: caravan, onboarding: gift ? ('gift' as const) : null };
  });
  return { village, caravan: result };
}

// Sends empty caravans to the vault to bring back `load` (or as much of it
// as the vault holds when they get there).
export async function fetchFromVaultCommand(
  db: Db,
  deps: SchedulerDeps,
  input: VillageCommandInput & { load: Resources; escort?: Record<string, number> | undefined },
): Promise<{ village: Village; caravan: Caravan }> {
  const { village, result } = await ownVillageCommand(db, deps, { ...input, action: 'sent caravans to the vault' }, async ({ client, world, village }) => {
    const state = withEscort(deps.data, village.state, input.escort, input.now, world.speed);
    const caravan = await dispatchCaravan(
      client,
      deps.data,
      world,
      village,
      'fetch',
      { destinationVillageId: null, load: input.load, escort: input.escort },
      input.now,
    );
    return { state, result: caravan };
  });
  return { village, caravan: result };
}

// Any member can start the vault's next level, paid from the vault.
export async function upgradeVaultCommand(
  db: Db,
  deps: SchedulerDeps,
  input: { worldId: number; now: Date },
): Promise<Vault> {
  return withWorld(db, input.worldId, input.now, deps, async (client) => {
    const world = (await client.query<{ speed: number }>('SELECT speed FROM worlds WHERE id = $1', [input.worldId])).rows[0]!;
    const vault = await loadVault(client, input.worldId);
    if (vault.upgradingTo !== null) throw new RuleError('The vault is already being enlarged');
    if (vault.level >= deps.data.logistics.vault.maxLevel) throw new RuleError('The vault is as large as it gets');
    const target = vault.level + 1;
    const cost = vaultUpgradeCost(deps.data, target);
    const missing = RESOURCE_KINDS.filter((kind) => vault.amounts[kind] < cost[kind]);
    if (missing.length) throw new RuleError(`The vault needs more ${missing.join(', ')} for that`);
    const completesAt = new Date(input.now.getTime() + vaultUpgradeMs(deps.data, target, world.speed));
    const next: Vault = {
      ...vault,
      amounts: withdraw(vault.amounts, cost).amounts,
      upgradingTo: target,
      upgradeCompletesAt: completesAt,
    };
    await saveVault(client, next);
    await scheduleEvent(client, input.worldId, completesAt, 'vault_upgrade', {});
    await notifyWorld(client, { worldId: input.worldId, type: 'caravans' });
    return next;
  });
}
