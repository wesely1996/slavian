import type { GameData, TerrainId } from '../data/index.js';
import { caravansOut, insertCaravan, type Caravan } from '../db/caravans.js';
import { effectiveBonuses } from '../db/heroes.js';
import { notifyWorld } from '../db/notify.js';
import type { Db, DbClient } from '../db/pool.js';
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
  vaultUpgradeCost,
  vaultUpgradeMs,
  withdraw,
} from '../sim/logistics.js';
import { RESOURCE_KINDS, spend, type Resources } from '../sim/resources.js';
import { sendAway, type VillageState } from '../sim/village.js';
import { ownVillageCommand, type VillageCommandInput } from './village.js';

// Where a caravan goes: an allied village, or the vault when null.
export interface CaravanOrder {
  destinationVillageId: number | null;
  load: Resources;
  // Troops guarding it against camps on the road.
  escort?: Record<string, number> | undefined;
}

// Sends the escort away with the caravan (they come back with it).
function withEscort(data: GameData, state: VillageState, escort: Record<string, number> | undefined, at: Date): VillageState {
  let next = state;
  for (const [unit, n] of Object.entries(escort ?? {})) {
    if (n <= 0) continue;
    if (!fighters(data, { [unit]: 1 })[unit]) throw new RuleError(`${data.units.units[unit]?.name ?? unit} can't guard caravans`);
    next = sendAway(next, unit, n, at);
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
  if (order.destinationVillageId !== null) {
    if (order.destinationVillageId === village.id) throw new RuleError('Send it to another village');
    const destination = await loadVillage(client, order.destinationVillageId).catch(() => null);
    if (!destination || destination.worldId !== world.id) throw new NotFoundError('No such village in this world');
    to = hex(destination.q, destination.r);
  }
  const terrain = new Map<string, TerrainId>((await loadHexes(client, world.id)).map(([q, r, t]) => [`${q},${r}`, t]));
  const path = caravanRoute(data, terrain, hex(village.q, village.r), to, world.speed, bonuses);
  const travelMs = path.at(-1)!.atMs;
  const arrivesAt = new Date(now.getTime() + travelMs);
  const caravan = await insertCaravan(client, {
    worldId: world.id,
    villageId: village.id,
    destinationVillageId: order.destinationVillageId,
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

// Loads resources from the caravan's village and sends them to an ally or
// the Holy City vault.
export async function sendCaravanCommand(
  db: Db,
  deps: SchedulerDeps,
  input: VillageCommandInput & CaravanOrder,
): Promise<{ village: Village; caravan: Caravan }> {
  const { village, result } = await ownVillageCommand(db, deps, { ...input, action: 'sent a caravan' }, async ({ client, world, village }) => {
    const escorted = withEscort(deps.data, village.state, input.escort, input.now);
    const caravan = await dispatchCaravan(client, deps.data, world, village, 'deliver', input, input.now);
    const state: VillageState = { ...escorted, ledger: spend(escorted.ledger, input.now, input.load) };
    return { state, result: caravan };
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
    const state = withEscort(deps.data, village.state, input.escort, input.now);
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
