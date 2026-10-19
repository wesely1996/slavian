// Scripted players for the headless simulator (PLAN.md §13). Each turn a
// bot looks at the world as it stands and gives the orders a sensible
// player of its kind would: keep building, keep a garrison, fill the vault
// and the bridge, and go after the bridge's quests. Refused orders (not
// enough resources, a full queue) are simply skipped.
import { buildFortCommand, sendArmyCommand } from '../commands/armies.js';
import { listForts } from '../db/forts.js';
import { sendCaravanCommand } from '../commands/logistics.js';
import { placeOrderCommand } from '../commands/orders.js';
import { foundVillageCommand, queueBuildCommand, rebuildCommand, startResearchCommand, trainUnitsCommand } from '../commands/village.js';
import type { GameData, TerrainId } from '../data/index.js';
import { findBridge } from '../db/bridges.js';
import { listCamps } from '../db/camps.js';
import { inTransaction, type Db, type DbClient } from '../db/pool.js';
import { listSites } from '../db/sites.js';
import { loadVault } from '../db/vaults.js';
import { caravanCapacity, caravansAt } from '../sim/logistics.js';
import { listVillages, type Village } from '../db/villages.js';
import { listActiveWaves } from '../db/waves.js';
import { getWorld, loadHexes, type World } from '../db/worlds.js';
import { listOrders } from '../db/orders.js';
import { listResearch } from '../db/research.js';
import { listArmies } from '../db/armies.js';
import { ForbiddenError, NotFoundError, RuleError } from '../errors.js';
import { craftRitualCommand, donateCommand } from '../scheduler/bridge.js';
import type { SchedulerDeps } from '../scheduler/events.js';
import { currentStage } from '../sim/bridge.js';
import { isChokePoint } from '../sim/field.js';
import { hex, hexDistance, type Hex } from '../sim/hex.js';
import { researchProblem } from '../sim/research.js';
import { amountsAt, InsufficientResourcesError, type Resources } from '../sim/resources.js';
import { buildQueueLimit, outpostLimit, outpostPlots, unlockedSlots } from '../sim/village.js';
import { claimOutpostCommand } from '../commands/village.js';

export const BOT_KINDS = ['turtle', 'expander', 'balanced'] as const;
export type BotKind = (typeof BOT_KINDS)[number];

interface Style {
  // Garrison to keep per village: base + per game day.
  garrisonBase: number;
  garrisonPerDay: number;
  // Villages to aim for.
  villages: number;
  // Center buildings, in the order they are wanted.
  buildings: string[];
}

const STYLES: Record<BotKind, Style> = {
  turtle: { garrisonBase: 20, garrisonPerDay: 8, villages: 1, buildings: ['barracks', 'storehouse', 'caravan_yard', 'scout_lodge', 'academy'] },
  expander: { garrisonBase: 6, garrisonPerDay: 3, villages: 5, buildings: ['barracks', 'settlers_lodge', 'storehouse', 'caravan_yard', 'scout_lodge', 'academy'] },
  balanced: { garrisonBase: 12, garrisonPerDay: 5, villages: 3, buildings: ['barracks', 'storehouse', 'caravan_yard', 'scout_lodge', 'academy', 'settlers_lodge'] },
};

const FIELDS = ['woodcutter', 'quarry', 'farm', 'iron_mine'];
const KINDS = ['wood', 'stone', 'grain', 'iron'] as const;

export interface Bot {
  accountId: number;
  name: string;
  kind: BotKind;
}

export interface TurnContext {
  db: Db;
  deps: SchedulerDeps;
  world: World;
  terrain: Map<string, TerrainId>;
  now: Date;
  day: number;
}

// Runs a command; a refusal (rules, ownership, a vanished target) is a
// normal outcome for a bot and is only counted.
async function attempt(counter: { refused: number }, fn: () => Promise<unknown>): Promise<boolean> {
  try {
    await fn();
    return true;
  } catch (error) {
    if (error instanceof RuleError || error instanceof ForbiddenError || error instanceof NotFoundError || error instanceof InsufficientResourcesError) {
      if (error instanceof InsufficientResourcesError) error.message = 'Not enough resources';
      counter.refused++;
      const reason = error.message.replace(/\d+/g, 'N');
      stats.reasons[reason] = (stats.reasons[reason] ?? 0) + 1;
      return false;
    }
    throw error;
  }
}

// Strong points the group has picked, by world: teammates hold them together.
const strongPoints = new Map<number, { q: number; r: number; until: number }>();

export const stats = { refused: 0, commands: 0, reasons: {} as Record<string, number> };

// Reads with a pooled client.
function read<T>(db: Db, fn: (client: DbClient) => Promise<T>): Promise<T> {
  return inTransaction(db, fn);
}

function garrisonSize(village: Village): number {
  const fighting = Object.entries(village.state.garrison).filter(([unit]) => unit !== 'scout' && unit !== 'settler');
  const training = village.state.training.filter((b) => b.unit !== 'scout' && b.unit !== 'settler').reduce((n, b) => n + b.count, 0);
  return fighting.reduce((n, [, c]) => n + c, 0) + training;
}

// The bot's own villages, oldest first.
async function ownVillages(ctx: TurnContext, bot: Bot): Promise<Village[]> {
  return (await read(ctx.db, (c) => listVillages(c, ctx.world.id))).filter((v) => v.ownerAccountId === bot.accountId).sort((a, b) => a.id - b.id);
}

export async function playTurn(ctx: TurnContext, bot: Bot): Promise<void> {
  const style = STYLES[bot.kind];
  const { db, deps, now } = ctx;
  const go = (fn: () => Promise<unknown>) => {
    stats.commands++;
    return attempt(stats, fn);
  };
  const villages = await ownVillages(ctx, bot);
  for (const village of villages) {
    const base = { accountId: bot.accountId, villageId: village.id, now };
    if (village.ruin) {
      await go(() => rebuildCommand(db, deps, base));
      continue;
    }
    const levels = village.state.levels;
    const amounts = amountsAt(village.state.ledger, now);
    const capacity = village.state.ledger.capacity;

    // Building: keep the queue busy.
    const hall = levels.elder_hall ?? 0;
    let free = buildQueueLimit(deps.data, hall) - village.state.queue.length;
    for (const choice of buildChoices(deps.data, village, style, amounts, capacity, ctx.day)) {
      if (free <= 0) break;
      if (await go(() => queueBuildCommand(db, deps, { ...base, building: choice }))) free--;
    }

    // Defenders: spearmen and archers, some horsemen once the barracks allows.
    const target = style.garrisonBase + style.garrisonPerDay * ctx.day;
    const missing = target - garrisonSize(village);
    if (missing > 0 && (levels.barracks ?? 0) > 0) {
      const unit = (levels.barracks ?? 0) >= 2 && ctx.day % 3 === 2 ? 'horseman' : ctx.day % 2 === 0 ? 'spearman' : 'archer';
      // As many as half the stores can pay for: building goes on too.
      const cost = deps.data.units.units[unit]!.cost;
      const affordable = Math.min(...KINDS.filter((k) => cost[k] > 0).map((k) => Math.floor((amounts[k] * 0.5) / cost[k])));
      const count = Math.min(missing, deps.data.units.maxBatch, 20, affordable);
      if (count > 0) await go(() => trainUnitsCommand(db, deps, { ...base, unit, count }));
    }
    if ((levels.scout_lodge ?? 0) > 0 && (village.state.garrison.scout ?? 0) < 4 && !village.state.training.some((b) => b.unit === 'scout')) {
      await go(() => trainUnitsCommand(db, deps, { ...base, unit: 'scout', count: 4 }));
    }

    // Standing orders: rebuild raided outposts; send surplus to the vault.
    const orders = await read(db, (c) => listOrders(c, { villageId: village.id }));
    if (!orders.some((o) => o.spec.kind === 'rebuild')) {
      await go(() => placeOrderCommand(db, deps, { ...base, spec: { kind: 'rebuild' } }));
    }
    if ((levels.caravan_yard ?? 0) > 0 && !orders.some((o) => o.spec.kind === 'surplus')) {
      await go(() => placeOrderCommand(db, deps, { ...base, spec: { kind: 'surplus', share: 0.6 } }));
    }

    // Research: the cheapest tech open to us.
    if ((levels.academy ?? 0) > 0) await research(ctx, bot, village);

    // Outposts on rich hexes nearby.
    if (outpostPlots(village.state.plots).length < outpostLimit(deps.data, hall) && ctx.day >= 1) {
      const cell = await outpostSite(ctx, village);
      if (cell) await go(() => claimOutpostCommand(db, deps, { ...base, q: cell.q, r: cell.r }));
    }
  }

  // Expansion: settlers from the oldest village.
  const home = villages.find((v) => !v.ruin);
  if (home && villages.length < style.villages && (home.state.levels.settlers_lodge ?? 0) > 0) {
    const base = { accountId: bot.accountId, villageId: home.id, now };
    const settlers = home.state.garrison.settler ?? 0;
    const needed = deps.data.expansion.settlersNeeded;
    if (settlers >= needed) {
      const cell = await settleSite(ctx, home);
      if (cell) await go(() => foundVillageCommand(db, deps, { ...base, q: cell.q, r: cell.r }));
    } else if (!home.state.training.some((b) => b.unit === 'settler')) {
      await go(() => trainUnitsCommand(db, deps, { ...base, unit: 'settler', count: needed - settlers }));
    }
  }

  if (home) await bridgeWork(ctx, bot, home, go);
}

// What to build next, best first; the bot tries them in turn.
function buildChoices(
  data: GameData,
  village: Village,
  style: Style,
  amounts: Resources,
  capacity: Resources,
  day: number,
): string[] {
  const levels = village.state.levels;
  const queued = new Set(village.state.queue.map((q) => q.building));
  const hall = levels.elder_hall ?? 0;
  const used = Object.entries(village.state.plots).filter(([id, p]) => id.startsWith('c') && (p.building || queued.has(p.building ?? ''))).length;
  const freeSlots = unlockedSlots(data, hall) - used - village.state.queue.filter((q) => !levels[q.building]).length;
  const out: string[] = [];
  const add = (b: string) => {
    if (!queued.has(b) && !out.includes(b)) out.push(b);
  };
  const fieldAvg = FIELDS.reduce((n, f) => n + fieldLevel(village, f), 0) / FIELDS.length;
  // Storage when something is near full.
  const storeMax = data.buildings.buildings.storehouse!.maxLevel;
  if (KINDS.some((k) => amounts[k] > capacity[k] * 0.8) && (levels.storehouse ?? 0) > 0 && (levels.storehouse ?? 0) < storeMax) add('storehouse');
  // Economy first in the opening.
  if (fieldAvg < 2) for (const f of fieldsByNeed(data, village, amounts)) add(f);
  if (freeSlots > 0) for (const b of style.buildings) if ((levels[b] ?? 0) === 0) add(b);
  if (freeSlots <= 0 || hall < 2 + Math.floor(fieldAvg / 2)) add('elder_hall');
  if ((levels.barracks ?? 0) > 0 && (levels.barracks ?? 0) < Math.min(8, 1 + Math.floor(day / 3))) add('barracks');
  if ((levels.caravan_yard ?? 0) > 0 && (levels.caravan_yard ?? 0) < Math.min(5, 1 + Math.floor(day / 5))) add('caravan_yard');
  if ((levels.storehouse ?? 0) > 0 && (levels.storehouse ?? 0) < Math.min(storeMax, 1 + Math.floor(fieldAvg))) add('storehouse');
  for (const f of fieldsByNeed(data, village, amounts)) add(f);
  return out.slice(0, 4);
}

// Fields below max level, the scarcest resource first (iron is needed less).
function fieldsByNeed(data: GameData, village: Village, amounts: Resources): string[] {
  const need = (f: string) => amounts[fieldKind(data, f)] * (fieldKind(data, f) === 'iron' ? 1.6 : 1) + fieldLevel(village, f) * 40;
  return [...FIELDS].filter((f) => fieldLevel(village, f) < data.buildings.buildings[f]!.maxLevel).sort((a, b) => need(a) - need(b));
}

function fieldKind(data: GameData, field: string): (typeof KINDS)[number] {
  return data.buildings.buildings[field]!.production!.resource;
}

function fieldLevel(village: Village, field: string): number {
  const levels = Object.values(village.state.plots).filter((p) => p.building === field).map((p) => p.level);
  return levels.length ? Math.min(...levels) : 0;
}

async function research(ctx: TurnContext, bot: Bot, village: Village): Promise<void> {
  const entries = await read(ctx.db, (c) => listResearch(c, ctx.world.id, bot.accountId));
  if (entries.some((e) => e.status === 'researching')) return;
  const done = new Set(entries.filter((e) => e.status === 'done').map((e) => e.tech));
  const techs = Object.entries(ctx.deps.data.research.techs)
    .filter(([id]) => !done.has(id))
    .filter(([id]) => !researchProblem(ctx.deps.data, id, { academyLevel: village.state.levels.academy ?? 0, done, researching: false, scrolls: new Set() }))
    .sort(([, a], [, b]) => KINDS.reduce((n, k) => n + a.cost[k], 0) - KINDS.reduce((n, k) => n + b.cost[k], 0));
  const tech = techs[0]?.[0];
  if (tech) {
    stats.commands++;
    await attempt(stats, () => startResearchCommand(ctx.db, ctx.deps, { accountId: bot.accountId, villageId: village.id, tech, now: ctx.now }));
  }
}

// Hexes no village, outpost, camp or site holds.
async function takenHexes(ctx: TurnContext): Promise<Set<string>> {
  const taken = new Set<string>();
  for (const v of await read(ctx.db, (c) => listVillages(c, ctx.world.id))) {
    taken.add(`${v.q},${v.r}`);
    for (const plot of outpostPlots(v.state.plots)) taken.add(plot.slice(1));
  }
  for (const c of await read(ctx.db, (c) => listCamps(c, ctx.world.id))) taken.add(`${c.q},${c.r}`);
  for (const s of await read(ctx.db, (c) => listSites(c, ctx.world.id))) taken.add(`${s.q},${s.r}`);
  return taken;
}

async function outpostSite(ctx: TurnContext, village: Village): Promise<Hex | null> {
  const yields = ctx.deps.data.buildings.buildings.outpost!.yields!;
  const taken = await takenHexes(ctx);
  const home = hex(village.q, village.r);
  let best: Hex | null = null;
  for (const [key, terrain] of ctx.terrain) {
    if (!yields[terrain] || taken.has(key)) continue;
    const [q, r] = key.split(',').map(Number);
    const cell = hex(q!, r!);
    const d = hexDistance(cell, home);
    if (d < 1 || d > ctx.deps.data.buildings.village.outpostRange) continue;
    if (!best || d < hexDistance(best, home)) best = cell;
  }
  return best;
}

async function settleSite(ctx: TurnContext, home: Village): Promise<Hex | null> {
  const rules = ctx.deps.data.expansion;
  const villages = await read(ctx.db, (c) => listVillages(c, ctx.world.id));
  const taken = await takenHexes(ctx);
  const from = hex(home.q, home.r);
  let best: Hex | null = null;
  for (const [key, terrain] of ctx.terrain) {
    if (!ctx.deps.data.terrain.terrain[terrain].settleable || taken.has(key)) continue;
    const [q, r] = key.split(',').map(Number);
    const cell = hex(q!, r!);
    const d = hexDistance(cell, from);
    if (d > rules.maxDistance || hexDistance(cell, hex(0, 0)) < Math.max(rules.minHolyCityDistance, 3)) continue;
    if (villages.some((v) => hexDistance(cell, hex(v.q, v.r)) < rules.minVillageDistance)) continue;
    // Close to home, but not on the border.
    if (!best || d < hexDistance(best, from) || (d === hexDistance(best, from) && hexDistance(cell, hex(0, 0)) < hexDistance(best, hex(0, 0)))) best = cell;
  }
  return best;
}

// The bridge: give the vault to the stage, then chase its quests.
async function bridgeWork(ctx: TurnContext, bot: Bot, home: Village, go: (fn: () => Promise<unknown>) => Promise<boolean>): Promise<void> {
  const { db, deps, now } = ctx;
  const world = await read(db, (c) => getWorld(c, ctx.world.id));
  const bridge = await read(db, (c) => findBridge(c, world.id));
  if (!bridge || bridge.status !== 'open') return;
  const stage = currentStage(deps.data, bridge);
  if (!stage) return;
  const vault = (await read(db, (c) => loadVault(c, world.id))).amounts;
  const give: Resources = { wood: 0, stone: 0, grain: 0, iron: 0 };
  for (const k of KINDS) give[k] = Math.max(0, Math.min(Math.floor(vault[k]), stage.cost[k] - (bridge.donated[k] ?? 0)));
  const embers = Math.min(world.embers, Math.max(0, stage.embers - bridge.embers));
  if (KINDS.some((k) => give[k] > 0) || embers > 0) {
    await go(() => donateCommand(db, deps, { accountId: bot.accountId, worldId: world.id, resources: give, embers, now }));
  }
  const open = stage.quests.map((q) => q.kind).filter((k) => !bridge.quests[k]);
  if (open.includes('ritual') && world.embers >= deps.data.bridge.ritualEmbers) {
    await go(() => craftRitualCommand(db, deps, { accountId: bot.accountId, worldId: world.id, now }));
  }
  const all = (await read(db, (c) => listArmies(c, world.id))).filter((a) => a.homeVillageId === home.id && a.status !== 'done');
  const guardsCity = (a: (typeof all)[number]) => a.orders === 'hold' && a.targetQ === 0 && a.targetR === 0;
  // Armies out on errands (the Holy City's guard stays put).
  const armies = all.filter((a) => !guardsCity(a));
  const garrison = home.state.garrison;
  const fighters = (share: number): Record<string, number> => {
    const out: Record<string, number> = {};
    for (const unit of ['spearman', 'archer', 'horseman']) {
      const n = Math.floor((garrison[unit] ?? 0) * share);
      if (n > 0) out[unit] = n;
    }
    return out;
  };
  const strength = (units: Record<string, number>) => Object.entries(units).reduce((n, [u, c]) => n + c * (deps.data.units.units[u]?.attack ?? 0), 0);
  const base = { accountId: bot.accountId, villageId: home.id, targetVillageId: null, now };
  const from = hex(home.q, home.r);

  // Once the hordes grow, part of the army stands with the Holy City's guard.
  if (ctx.day >= 15 && !all.some(guardsCity)) {
    const army = fighters(0.35);
    if (strength(army) > 0) await go(() => sendArmyCommand(db, deps, { ...base, target: hex(0, 0), units: army, orders: 'hold' }));
  }
  // Hold a strong point on a horde's road: a choke, or a fort built there.
  if (open.includes('choke') && !armies.some((a) => a.orders === 'hold')) {
    // The group's strong point, if a teammate already picked one: join them there.
    const shared = strongPoints.get(world.id);
    if (shared && shared.until > now.getTime()) {
      const army = fighters(0.9);
      if (strength(army) > 0 && (await go(() => sendArmyCommand(db, deps, { ...base, target: hex(shared.q, shared.r), units: army, orders: 'hold' })))) return;
    }
    // Most of the army: late hordes are strong.
    const forts = await read(db, (c) => listForts(c, world.id));
    const taken = await takenHexes(ctx);
    const range = deps.data.field.fort.range;
    for (const wave of await read(db, (c) => listActiveWaves(c, world.id))) {
      if (wave.status !== 'marching' || !wave.path) continue;
      const sinceSpawn = now.getTime() - wave.spawnAt.getTime();
      // Far enough ahead to build a fort and march there.
      const ahead = wave.path.filter((s) => s.atMs > sinceSpawn + (3 * 3_600_000) / world.speed);
      const near = (s: { q: number; r: number }) => hexDistance(hex(s.q, s.r), from);
      const choke = ahead.find((s) => near(s) <= 5 && isChokePoint(deps.data, ctx.terrain, hex(s.q, s.r)));
      const fort = ahead.find((s) => forts.some((f) => f.q === s.q && f.r === s.r && f.villageId === home.id));
      let step = choke ?? fort;
      if (!step) {
        const site = ahead.find((s) => near(s) >= 1 && near(s) <= range && !taken.has(`${s.q},${s.r}`) && ctx.terrain.get(`${s.q},${s.r}`) !== 'holy_city');
        if (site && (await go(() => buildFortCommand(db, deps, { accountId: bot.accountId, villageId: home.id, cell: hex(site.q, site.r), now })))) step = site;
      }
      if (!step) continue;
      const target = step;
      strongPoints.set(world.id, { q: target.q, r: target.r, until: wave.spawnAt.getTime() + target.atMs });
      const army = fighters(0.9);
      if (strength(army) > 0 && (await go(() => sendArmyCommand(db, deps, { ...base, target: hex(target.q, target.r), units: army, orders: 'hold' })))) return;
    }
  }
  if (armies.length > 0) return;
  // Explore ancient sites (for the relic, Embers and scrolls): scouts where no
  // guardians are known, an army otherwise.
  const wantsSite = open.includes('site') || world.embers < deps.data.bridge.ritualEmbers + stage.embers;
  if (wantsSite) {
    const sites = (await read(db, (c) => listSites(c, world.id))).filter((s) => s.status === 'unexplored').sort((a, b) => hexDistance(hex(a.q, a.r), from) - hexDistance(hex(b.q, b.r), from));
    const site = sites[0];
    if (site) {
      const guarded = site.guardiansSeen && Object.values(site.guardians).some((n) => n > 0);
      const units: Record<string, number> = guarded || !site.guardiansSeen ? fighters(0.5) : { scout: Math.min(3, garrison.scout ?? 0) };
      if (!guarded && site.guardiansSeen && (garrison.scout ?? 0) > 0) units.scout = Math.min(3, garrison.scout ?? 0);
      if (strength(units) > 0 || (units.scout ?? 0) > 0) {
        if (await go(() => sendArmyCommand(db, deps, { ...base, target: hex(site.q, site.r), units, orders: 'explore' }))) return;
      }
    }
  }
  // Clear a lair when the stage asks for it (or any camp close to home).
  const camps = (await read(db, (c) => listCamps(c, world.id))).sort((a, b) => hexDistance(hex(a.q, a.r), from) - hexDistance(hex(b.q, b.r), from));
  const embersShort = world.embers < deps.data.bridge.ritualEmbers + Math.max(0, stage.embers - bridge.embers);
  const lair = open.includes('lair') || embersShort ? camps.find((c) => c.kind === 'lair') : camps.find((c) => hexDistance(hex(c.q, c.r), from) <= 4);
  if (lair) {
    const army = fighters(0.7);
    const campPower = Object.entries(lair.units).reduce((n, [, c]) => n + c, 0) * 25;
    if (strength(army) > campPower * 1.5) {
      if (await go(() => sendArmyCommand(db, deps, { ...base, target: hex(lair.q, lair.r), units: army, orders: 'clear' }))) return;
    }
  }

}

// The terrain of a world, by "q,r".
export async function terrainOf(db: Db, worldId: number): Promise<Map<string, TerrainId>> {
  return new Map((await read(db, (c) => loadHexes(c, worldId))).map(([q, r, t]) => [`${q},${r}`, t]));
}

// Caravans: a tithe towards what the bridge stage still lacks (beyond what
// the vault already holds), up to `share` of each village's stores.
export async function feedVault(ctx: TurnContext, bot: Bot, share = 0.3): Promise<void> {
  const bridge = await read(ctx.db, (c) => findBridge(c, ctx.world.id));
  const stage = bridge && bridge.status !== 'complete' ? currentStage(ctx.deps.data, bridge) : null;
  if (!bridge || !stage) return;
  const vault = (await read(ctx.db, (c) => loadVault(c, ctx.world.id))).amounts;
  const lacking: Resources = { wood: 0, stone: 0, grain: 0, iron: 0 };
  for (const k of KINDS) lacking[k] = Math.max(0, stage.cost[k] - (bridge.donated[k] ?? 0) - Math.floor(vault[k]));
  for (const village of await ownVillages(ctx, bot)) {
    if ((village.state.levels.caravan_yard ?? 0) === 0 || village.ruin) continue;
    const amounts = amountsAt(village.state.ledger, ctx.now);
    const load: Resources = { wood: 0, stone: 0, grain: 0, iron: 0 };
    for (const k of KINDS) load[k] = Math.max(0, Math.min(lacking[k], Math.floor(amounts[k] * share)));
    // No more than the caravans at home can carry.
    const out = (await read(ctx.db, (c) => c.query<{ n: number }>("SELECT count(*)::int AS n FROM caravans WHERE village_id = $1 AND status <> 'done'", [village.id]))).rows[0]!.n;
    const room = (caravansAt(ctx.deps.data, village.state.levels.caravan_yard ?? 0) - out) * caravanCapacity(ctx.deps.data, village.state.bonuses);
    const total = KINDS.reduce((n, k) => n + load[k], 0);
    if (total > room) for (const k of KINDS) load[k] = Math.floor((load[k] * Math.max(0, room)) / total);
    // Not for a handful, unless it is all the stage still lacks.
    const sent = KINDS.reduce((n, k) => n + load[k], 0);
    if (sent >= Math.min(100, KINDS.reduce((n, k) => n + lacking[k], 0)) && sent > 0) {
      for (const k of KINDS) lacking[k] -= load[k];
      stats.commands++;
      await attempt(stats, () => sendCaravanCommand(ctx.db, ctx.deps, { accountId: bot.accountId, villageId: village.id, now: ctx.now, destinationVillageId: null, load }));
    }
  }
}
