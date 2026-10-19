// JSON shapes sent to clients. Timestamps are ISO strings; clients compute
// current resources from the ledger and their offset to `serverTime`.
import { listRoadEdges } from '../db/roads.js';
import { listRiverEdges } from '../db/rivers.js';
import { activeDelegations, recentDelegationLog } from '../db/delegations.js';
import { runSummary } from '../db/runs.js';
import { listForts, type Fort } from '../db/forts.js';
import { listCamps } from '../db/camps.js';
import { loadFear } from '../db/fear.js';
import { listScrolls, listSites } from '../db/sites.js';
import { findBridge } from '../db/bridges.js';
import { newBridge } from '../sim/bridge.js';
import { total } from '../sim/battle.js';
import type { DbClient } from '../db/pool.js';
import type { Village } from '../db/villages.js';
import { batchCompletesAt } from '../sim/training.js';
import { listVillages } from '../db/villages.js';
import { listRecentBattles, type Battle } from '../db/battles.js';
import { listRecentRaids, type Raid } from '../db/raids.js';
import { listCaravans, type Caravan } from '../db/caravans.js';
import { listExpeditions, type Expedition } from '../db/expeditions.js';
import { listResearch, type ResearchEntry } from '../db/research.js';
import { listHeroes, type Hero } from '../db/heroes.js';
import { listOrders, type StoredOrder } from '../db/orders.js';
import { listArmies, type Army } from '../db/armies.js';
import { listNotifications, unreadCount, type Notification } from '../db/notifications.js';
import { heroBonuses, xpToNext } from '../sim/heroes.js';
import { loadVault, type Vault } from '../db/vaults.js';
import type { GameData } from '../data/index.js';
import { vaultCapacity } from '../sim/logistics.js';
import { listMissions, type ScoutMission } from '../db/scouting.js';
import { listActiveWaves, type Wave } from '../db/waves.js';
import { listMembers, loadHexes, quietWindow, type World } from '../db/worlds.js';

export interface VillageView {
  id: number;
  worldId: number;
  ownerAccountId: number | null;
  name: string;
  q: number;
  r: number;
  // Fields "f0"…, center slots "c0"… and outposts "o<q>,<r>" (with the
  // terrain of their hex).
  plots: Record<string, { building: string | null; level: number; terrain?: string }>;
  levels: Record<string, number>;
  queue: { plot: string; building: string; targetLevel: number; startsAt: string; completesAt: string }[];
  // Units at home as of the last settle; units finished since are counted
  // from `training` (each batch trains one unit every perUnitMs).
  garrison: Record<string, number>;
  away: Record<string, number>;
  stance: string;
  // A battle at the gates: outposts produce nothing until it ends.
  besieged: boolean;
  // Grain per hour (world speed 1) for administration (founded villages).
  adminUpkeep: number;
  // The owner's research effects.
  bonuses: Record<string, number>;
  // Troops sent to battles nearby: this share, within this many hexes.
  reinforce: { share: number; range: number } | null;
  // Razed: what stood (plots), since when, and while rebuilding when it
  // stands again; with what rebuilding costs.
  // A refugee camp: hordes raid it but never raze it.
  refuge: boolean;
  ruin: { plots: Record<string, { building: string | null; level: number }>; since: string; rebuildingUntil: string | null } | null;
  training: { unit: string; count: number; startsAt: string; perUnitMs: number; completesAt: string }[];
  resources: {
    amounts: Record<string, number>;
    ratesPerHour: Record<string, number>;
    capacity: Record<string, number>;
    settledAt: string;
  };
}

export function villageView(village: Village): VillageView {
  const { levels, queue, ledger, garrison, training } = village.state;
  return {
    id: village.id,
    worldId: village.worldId,
    ownerAccountId: village.ownerAccountId,
    name: village.name,
    q: village.q,
    r: village.r,
    plots: { ...village.state.plots },
    levels: { ...levels },
    queue: queue.map((item) => ({
      plot: item.plot,
      building: item.building,
      targetLevel: item.targetLevel,
      startsAt: item.startsAt.toISOString(),
      completesAt: item.completesAt.toISOString(),
    })),
    garrison: { ...garrison },
    away: { ...village.state.away },
    stance: village.state.stance,
    besieged: village.state.besieged,
    adminUpkeep: village.state.adminUpkeep,
    bonuses: { ...village.state.bonuses },
    reinforce: village.reinforce ?? null,
    ruin: village.ruin ?? null,
    refuge: village.refuge === true,
    training: training.map((batch) => ({
      unit: batch.unit,
      count: batch.count,
      startsAt: batch.startsAt.toISOString(),
      perUnitMs: batch.perUnitMs,
      completesAt: batchCompletesAt(batch).toISOString(),
    })),
    resources: {
      amounts: ledger.amounts,
      ratesPerHour: ledger.ratesPerHour,
      capacity: ledger.capacity,
      settledAt: ledger.settledAt.toISOString(),
    },
  };
}

// What everyone knows about a wave. Its composition stays hidden until
// scouted (M1 step 4).
export function waveView(wave: Wave) {
  return {
    id: wave.id,
    index: wave.index,
    front: wave.front,
    status: wave.status,
    threat: wave.threat,
    spawnAt: wave.spawnAt.toISOString(),
    spawn: wave.spawn,
    targetVillageId: wave.targetVillageId,
    // Each step: [q, r, ms after spawnAt when the horde enters that hex].
    path: wave.path?.map((step) => [step.q, step.r, step.atMs]) ?? null,
    arrivesAt: wave.arrivesAt?.toISOString() ?? null,
    endsAt: wave.endsAt?.toISOString() ?? null,
    // Its rampage clock (from its first target) and the villages it struck.
    rampageEndsAt: wave.rampageEndsAt?.toISOString() ?? null,
    struck: wave.struck,
    ritual: wave.ritual,
  };
}

export async function wavesView(client: DbClient, worldId: number) {
  return (await listActiveWaves(client, worldId)).map(waveView);
}

// Scout missions and their reports are shared with the whole group.
export function missionView(mission: ScoutMission) {
  return {
    id: mission.id,
    villageId: mission.villageId,
    waveId: mission.waveId,
    sent: mission.sent,
    status: mission.status,
    target: mission.target,
    departsAt: mission.departsAt.toISOString(),
    arrivesAt: mission.arrivesAt.toISOString(),
    returnsAt: mission.returnsAt.toISOString(),
    report: mission.report,
  };
}

export async function scoutingView(client: DbClient, worldId: number) {
  return (await listMissions(client, worldId)).map(missionView);
}

// Battles are fought in the open: both sides' numbers are visible.
export function battleView(battle: Battle, attackerNow: Record<string, number>) {
  return {
    id: battle.id,
    waveId: battle.waveId,
    campId: battle.campId,
    siteId: battle.siteId,
    villageId: battle.villageId,
    q: battle.q,
    r: battle.r,
    setup: battle.setup,
    status: battle.status,
    round: battle.round,
    attackerStance: battle.attackerStance,
    attackerInitial: battle.attackerInitial,
    attackerNow,
    defenderInitial: battle.defenderInitial,
    rounds: battle.rounds,
    loot: battle.loot,
    decision: battle.decision,
    startedAt: battle.startedAt.toISOString(),
    endedAt: battle.endedAt?.toISOString() ?? null,
  };
}

export async function battlesView(client: DbClient, worldId: number) {
  const battles = await listRecentBattles(client, worldId);
  const waves = new Map<number, Record<string, number>>();
  if (battles.length) {
    const { rows } = await client.query<{ id: number; composition: Record<string, number> }>(
      'SELECT id, composition FROM waves WHERE id = ANY($1)',
      [battles.map((b) => b.waveId).filter((id) => id !== null)],
    );
    for (const row of rows) waves.set(row.id, row.composition);
  }
  // A camp's numbers after the assault: its start minus what fell.
  const after = (battle: Battle) => {
    const left: Record<string, number> = { ...battle.attackerInitial };
    for (const round of battle.rounds) for (const [unit, n] of Object.entries(round.attackerLosses)) left[unit] = (left[unit] ?? 0) - n;
    return Object.fromEntries(Object.entries(left).filter(([, n]) => n > 0));
  };
  return battles.map((battle) => battleView(battle, battle.waveId === null ? after(battle) : (waves.get(battle.waveId) ?? {})));
}

export function raidView(raid: Raid) {
  return {
    id: raid.id,
    waveId: raid.waveId,
    villageId: raid.villageId,
    q: raid.q,
    r: raid.r,
    levelAfter: raid.levelAfter,
    at: raid.at.toISOString(),
  };
}

export async function raidsView(client: DbClient, worldId: number) {
  return (await listRecentRaids(client, worldId)).map(raidView);
}

export function caravanView(caravan: Caravan) {
  return {
    id: caravan.id,
    villageId: caravan.villageId,
    // null: the Holy City vault.
    destinationVillageId: caravan.destinationVillageId,
    kind: caravan.kind,
    caravans: caravan.caravans,
    cargo: caravan.cargo,
    carriedBack: caravan.carriedBack,
    status: caravan.status,
    // Each step: [q, r, ms after departsAt]; the way home is the same road
    // backwards, starting at arrivesAt.
    path: caravan.path.map((step) => [step.q, step.r, step.atMs]),
    departsAt: caravan.departsAt.toISOString(),
    arrivesAt: caravan.arrivesAt.toISOString(),
    returnsAt: caravan.returnsAt.toISOString(),
    // Troops guarding it, and what happened if a camp ambushed it.
    escort: caravan.escort,
    ambush: caravan.ambush,
  };
}

export function vaultView(data: GameData, vault: Vault) {
  return {
    level: vault.level,
    amounts: vault.amounts,
    capacity: vaultCapacity(data, vault.level),
    upgradingTo: vault.upgradingTo,
    upgradeCompletesAt: vault.upgradeCompletesAt?.toISOString() ?? null,
  };
}

export async function logisticsView(client: DbClient, data: GameData, worldId: number) {
  return {
    caravans: (await listCaravans(client, worldId)).map(caravanView),
    vault: vaultView(data, await loadVault(client, worldId)),
  };
}

export function expeditionView(expedition: Expedition) {
  return {
    id: expedition.id,
    villageId: expedition.villageId,
    q: expedition.q,
    r: expedition.r,
    name: expedition.name,
    settlers: expedition.settlers,
    status: expedition.status,
    failure: expedition.failure,
    foundedVillageId: expedition.foundedVillageId,
    // Like caravans: [q, r, ms after departsAt]; home is the road backwards.
    path: expedition.path.map((step) => [step.q, step.r, step.atMs]),
    departsAt: expedition.departsAt.toISOString(),
    arrivesAt: expedition.arrivesAt.toISOString(),
    returnsAt: expedition.returnsAt.toISOString(),
  };
}

export async function expeditionsView(client: DbClient, worldId: number) {
  return (await listExpeditions(client, worldId)).map(expeditionView);
}

// Everyone's research is visible to the group (co-op specialization).
export function researchView(entry: ResearchEntry) {
  return {
    accountId: entry.accountId,
    tech: entry.tech,
    status: entry.status,
    villageId: entry.villageId,
    startedAt: entry.startedAt.toISOString(),
    completesAt: entry.completesAt.toISOString(),
  };
}

export async function researchListView(client: DbClient, worldId: number) {
  return (await listResearch(client, worldId)).map(researchView);
}

// Heroes are visible to the whole group.
export function heroView(data: GameData, hero: Hero) {
  return {
    accountId: hero.accountId,
    name: hero.name,
    status: hero.status,
    // Where it stands (or, travelling, where it is heading).
    villageId: hero.villageId,
    // Leading this army (status 'with_army').
    armyId: hero.armyId,
    level: hero.level,
    xp: hero.xp,
    xpToNext: hero.level >= data.heroes.maxLevel ? null : xpToNext(data, hero.level),
    skillPoints: hero.skillPoints,
    skills: hero.skills,
    gear: hero.gear,
    inventory: hero.inventory,
    // What it adds to the village it stands in.
    bonuses: heroBonuses(data, hero),
    path: hero.path?.map((step) => [step.q, step.r, step.atMs]) ?? null,
    departsAt: hero.departsAt?.toISOString() ?? null,
    arrivesAt: hero.arrivesAt?.toISOString() ?? null,
    woundedUntil: hero.woundedUntil?.toISOString() ?? null,
  };
}

export async function heroesView(client: DbClient, data: GameData, worldId: number) {
  return (await listHeroes(client, worldId)).map((hero) => heroView(data, hero));
}

export function orderView(order: StoredOrder) {
  return {
    id: order.id,
    villageId: order.villageId,
    ...order.spec,
    lastResult: order.lastResult,
    lastRunAt: order.lastRunAt?.toISOString() ?? null,
  };
}

export async function ordersView(client: DbClient, worldId: number) {
  return (await listOrders(client, { worldId })).map(orderView);
}

export function notificationView(n: Notification) {
  return {
    id: n.id,
    kind: n.kind,
    tier: n.tier,
    title: n.title,
    body: n.body,
    createdAt: n.createdAt.toISOString(),
    read: n.readAt !== null,
  };
}

// A player's own notifications in a world, newest first.
export async function inboxView(client: DbClient, accountId: number, worldId: number) {
  return {
    notifications: (await listNotifications(client, accountId, worldId)).map(notificationView),
    unread: await unreadCount(client, accountId, worldId),
  };
}

export function armyView(army: Army) {
  return {
    id: army.id,
    ownerAccountId: army.ownerAccountId,
    homeVillageId: army.homeVillageId,
    targetVillageId: army.targetVillageId,
    target: [army.targetQ, army.targetR],
    heroAccountId: army.heroAccountId,
    orders: army.orders,
    // Carried home from a cleared camp.
    loot: army.loot,
    units: army.units,
    status: army.status,
    battleId: army.battleId,
    // [q, r, ms after departsAt]; home is the same road backwards from leavesAt.
    path: army.path.map((step) => [step.q, step.r, step.atMs]),
    departsAt: army.departsAt.toISOString(),
    arrivesAt: army.arrivesAt.toISOString(),
    leavesAt: army.leavesAt?.toISOString() ?? null,
    returnsAt: army.returnsAt?.toISOString() ?? null,
  };
}

export async function armiesView(client: DbClient, worldId: number) {
  return (await listArmies(client, worldId)).map(armyView);
}

export function fortView(fort: Fort) {
  return {
    id: fort.id,
    ownerAccountId: fort.ownerAccountId,
    villageId: fort.villageId,
    q: fort.q,
    r: fort.r,
    status: fort.status,
    completesAt: fort.completesAt.toISOString(),
  };
}

export async function fortsView(client: DbClient, worldId: number) {
  return (await listForts(client, worldId)).map(fortView);
}

export function worldSummary(world: World) {
  return {
    id: world.id,
    name: world.name,
    status: world.status,
    inviteCode: world.inviteCode,
    speed: world.speed,
    maxPlayers: world.maxPlayers,
    hostAccountId: world.hostAccountId,
    startedAt: world.startedAt?.toISOString() ?? null,
    sanctity: world.sanctity,
    embers: world.embers,
    difficulty: world.difficulty,
    // Hordes don't arrive in the group's quiet hours (minutes after local midnight).
    quietHours: quietWindow(world),
    // When Ritual Night's hordes set out, and when the run ended.
    ritualAt: world.ritualAt?.toISOString() ?? null,
    endedAt: world.endedAt?.toISOString() ?? null,
  };
}

// Everything a member needs to render the world. Co-op: every member sees
// every village in full.
export async function worldView(client: DbClient, data: GameData, world: World, at: Date = new Date()) {
  const members = await listMembers(client, world.id);
  const villages = await listVillages(client, world.id);
  const waves = await wavesView(client, world.id);
  const scouting = await scoutingView(client, world.id);
  const battles = await battlesView(client, world.id);
  const raids = await raidsView(client, world.id);
  const expeditions = await expeditionsView(client, world.id);
  const research = await researchListView(client, world.id);
  const heroes = await heroesView(client, data, world.id);
  const orders = await ordersView(client, world.id);
  const armies = await armiesView(client, world.id);
  const forts = await fortsView(client, world.id);
  const camps = (await listCamps(client, world.id)).map((c) => ({ id: c.id, kind: c.kind, front: c.front, q: c.q, r: c.r, size: total(c.units), waveId: c.waveId }));
  const sites = (await listSites(client, world.id)).map((s) => ({
    id: s.id,
    kind: s.kind,
    q: s.q,
    r: s.r,
    status: s.status,
    // How many guard it, once someone has fought them (null: unknown).
    guardians: s.guardiansSeen ? total(s.guardians) : null,
    exploredBy: s.exploredBy,
    find: s.find,
    exploredAt: s.exploredAt?.toISOString() ?? null,
  }));
  const lore = (await listScrolls(client, world.id)).map((l) => ({ scroll: l.scroll, accountId: l.accountId, siteId: l.siteId, foundAt: l.foundAt.toISOString() }));
  const bridge = (await findBridge(client, world.id)) ?? (world.startedAt ? newBridge(world.startedAt, world.sanctity) : null);
  const fear = [...(await loadFear(client, world.id)).entries()].map(([key, value]) => [...key.split(',').map(Number), Math.round(value * 10) / 10]);
  const logistics = world.status === 'lobby' ? { caravans: [], vault: null } : await logisticsView(client, data, world.id);
  const map =
    world.status === 'lobby'
      ? null
      : {
          radius: world.radius,
          activeFronts: world.activeFronts,
          hexes: await loadHexes(client, world.id),
          // [aq, ar, bq, br, crossing]: river edges, and their bridges ('standing', 'building' or 'none').
          rivers: (await listRiverEdges(client, world.id)).map((e) => [e.a.q, e.a.r, e.b.q, e.b.r, e.crossing]),
          // [aq, ar, bq, br, status]: roads ('standing' or 'building').
          roads: (await listRoadEdges(client, world.id)).map((e) => [e.a.q, e.a.r, e.b.q, e.b.r, e.status]),
        };
  return {
    ...worldSummary(world),
    members: members.map((m) => ({ accountId: m.accountId, displayName: m.displayName, clan: m.clan, onboarding: m.onboarding })),
    villages: villages.map(villageView),
    waves,
    scouting,
    battles,
    raids,
    expeditions,
    research,
    heroes,
    orders,
    armies,
    forts,
    camps,
    // Ancient sites, and the group's lore scrolls.
    sites,
    lore,
    // The Kalinov Bridge (see sim/bridge.ts).
    bridge,
    // [q, r, fear]: where hordes were beaten, and how much they remember it.
    fear,
    // Hand-overs still running, and what delegates did lately.
    delegations: (await activeDelegations(client, world.id, at)).map((d) => ({ ...d, since: d.since.toISOString(), until: d.until.toISOString() })),
    delegationLog: (await recentDelegationLog(client, world.id)).map((e) => ({ ...e, at: e.at.toISOString() })),
    // How a finished run went (null while it goes on).
    run: await runSummary(client, world),
    ...logistics,
    map,
  };
}
