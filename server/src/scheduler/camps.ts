// Camps and lairs on the scheduler (PLAN.md §7.5): they appear when a wave
// ends (and from horde survivors and abandoned forts), grow (camp_grow),
// send part of themselves with the next wave of their front, ambush
// caravans passing close (caravan_ambush), and fall to armies sent to clear
// them, which carry their loot home.
import { z } from 'zod';
import type { GameData } from '../data/index.js';
import { armiesHolding, saveArmy, type Army } from '../db/armies.js';
import { insertBattle, recordRound, type RoundLog } from '../db/battles.js';
import { campAt, insertCamp, listCamps, loadCamp, markCleared, saveCampUnits, type Camp } from '../db/camps.js';
import { loadCaravan, recordAmbush, type Caravan } from '../db/caravans.js';
import { deleteFort, listForts, loadFort, markFortManned } from '../db/forts.js';
import { heroWithArmy } from '../db/heroes.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { listVillages, loadVillage, saveVillageState } from '../db/villages.js';
import { endWave, loadWave, reinforceWave, type Wave } from '../db/waves.js';
import { addEmbers, listMembers, type World } from '../db/worlds.js';
import { playerStats, total } from '../sim/battle.js';
import { ambush, assault, campLoot, campSize, feed, grow, passesCamp, spawnSites, addUnits } from '../sim/camps.js';
import { combine, heroBonuses } from '../sim/heroes.js';
import { hex, hexKey, type Hex } from '../sim/hex.js';
import { frontOf, type Front } from '../sim/mapgen.js';
import { emptyResources, mapResources, type Resources } from '../sim/resources.js';
import { receive } from '../sim/logistics.js';
import { loseAway } from '../sim/village.js';
import { composeWave, rngFor } from '../sim/waves.js';
import { armyLosses, sendHome, terrainOf } from './armies.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';
import { heroAfterBattle } from './heroes.js';
import { tell } from './notices.js';

const MS_PER_HOUR = 3_600_000;

export const campPayload = z.object({ campId: z.number().int() });
export const ambushPayload = z.object({ caravanId: z.number().int(), campId: z.number().int(), leg: z.enum(['out', 'back']) });
export type AmbushPayload = z.infer<typeof ambushPayload>;
export const fortCheckPayload = z.object({ fortId: z.number().int() });

function hoursMs(hours: number, worldSpeed: number): number {
  return (hours * MS_PER_HOUR) / worldSpeed;
}

// Every occupied hex: villages, outposts, forts and camps.
export async function occupiedHexes(client: DbClient, worldId: number): Promise<Set<string>> {
  const taken = new Set<string>();
  for (const v of await listVillages(client, worldId)) {
    taken.add(hexKey(hex(v.q, v.r)));
    for (const plot of Object.keys(v.state.plots)) if (plot.startsWith('o')) taken.add(plot.slice(1));
  }
  for (const f of await listForts(client, worldId)) taken.add(hexKey(hex(f.q, f.r)));
  for (const c of await listCamps(client, worldId)) taken.add(hexKey(hex(c.q, c.r)));
  return taken;
}

export async function createCamp(
  client: DbClient,
  data: GameData,
  world: World,
  camp: Pick<Camp, 'kind' | 'front' | 'q' | 'r' | 'units' | 'waveId'>,
  at: Date,
): Promise<Camp> {
  const created = await insertCamp(client, { ...camp, worldId: world.id, createdAt: at });
  await scheduleEvent(client, world.id, new Date(at.getTime() + hoursMs(data.camps.growth.everyHours, world.speed)), 'camp_grow', {
    campId: created.id,
  });
  await planAmbushesFor(client, data, world, created, at);
  await notifyWorld(client, { worldId: world.id, type: 'world' });
  return created;
}

// A wave is over: new camps of its front rise near its road.
async function spawnAfterWave(client: DbClient, data: GameData, world: World, wave: Wave, at: Date): Promise<void> {
  const rules = data.camps.spawn;
  const active = (await listCamps(client, world.id)).length;
  const count = Math.min(rules.perWave, rules.max - active);
  if (count <= 0 || !wave.path) return;
  const villages = (await listVillages(client, world.id)).map((v) => hex(v.q, v.r));
  const sites = spawnSites(data, {
    terrain: await terrainOf(client, world.id),
    path: wave.path,
    villages,
    taken: await occupiedHexes(client, world.id),
    rng: rngFor(world.seed, wave.index, 0xca),
    count,
  });
  const players = (await listMembers(client, world.id)).length;
  for (const [i, cell] of sites.entries()) {
    const units = composeWave(data, wave.front, wave.index, campSize(data, wave.index), world.seed ^ (0xc0 + i), players);
    await createCamp(client, data, world, { kind: wave.front === 'north' ? 'lair' : 'bandit', front: wave.front, q: cell.q, r: cell.r, units, waveId: wave.id }, at);
  }
}

// Ends a wave and lets its camps rise.
export async function finishWave(
  client: DbClient,
  data: GameData,
  world: World,
  waveId: number,
  status: 'defeated' | 'dispersed',
  at: Date,
): Promise<void> {
  await endWave(client, waveId, status, at);
  await spawnAfterWave(client, data, world, await loadWave(client, waveId), at);
}

export async function afterSettling(client: DbClient, data: GameData, world: World, waveId: number, at: Date): Promise<void> {
  await spawnAfterWave(client, data, world, await loadWave(client, waveId), at);
}

// A wave sets out: camps of its front send part of themselves along.
export async function campsJoin(client: DbClient, data: GameData, world: World, wave: Wave): Promise<void> {
  let composition = wave.composition;
  for (const camp of await listCamps(client, world.id)) {
    if (camp.front !== wave.front) continue;
    const { sent, kept } = feed(data, camp.units);
    if (total(sent) === 0) continue;
    composition = addUnits(composition, sent);
    await saveCampUnits(client, camp.id, kept);
  }
  if (composition !== wave.composition) await reinforceWave(client, wave.id, composition);
}

// --- Clearing ---------------------------------------------------------------

// An army sent to clear a camp has arrived: storm it.
export async function stormCamp(client: DbClient, data: GameData, world: World, army: Army, at: Date): Promise<void> {
  const camp = await campAt(client, world.id, army.targetQ, army.targetR);
  if (!camp) {
    await sendHome(client, world, army, at, data);
    return;
  }
  const home = await loadVillage(client, army.homeVillageId);
  const hero = await heroWithArmy(client, army.id);
  const bonuses = hero ? combine(home.state.bonuses, heroBonuses(data, hero)) : home.state.bonuses;
  const result = assault(data, {
    army: army.units,
    armyStats: playerStats(data, bonuses, false),
    armyStance: home.state.stance,
    camp: camp.units,
    front: camp.front as Front,
    seed: world.seed,
    id: camp.id,
  });
  // Reports keep the enemy as the attacker, like every other battle.
  const battle = await insertBattle(client, {
    worldId: world.id,
    waveId: null,
    campId: camp.id,
    villageId: null,
    q: camp.q,
    r: camp.r,
    attackerStance: data.camps.assault.stance,
    attackerInitial: camp.units,
    defenderInitial: army.units,
    startedAt: at,
  });
  for (const [i, round] of result.rounds.entries()) {
    const log: RoundLog = {
      round: round.round,
      at: at.toISOString(),
      attackerLosses: round.defenderLosses,
      defenderLosses: round.attackerLosses,
      attackerLeft: round.defenderLeft,
      defenderLeft: round.attackerLeft,
    };
    const last = i === result.rounds.length - 1;
    const loot = result.cleared ? campLoot(data, camp.units) : null;
    await recordRound(client, battle.id, log, last ? { status: result.cleared ? 'cleared' : 'repelled', at, loot } : null);
  }
  const lost: Record<string, number> = {};
  for (const [unit, n] of Object.entries(army.units)) if (n - (result.armyNow[unit] ?? 0) > 0) lost[unit] = n - (result.armyNow[unit] ?? 0);
  let after = await armyLosses(client, data, world, army, lost, at);
  const kills = total(camp.units) - total(result.campNow);
  const where = `${camp.kind === 'lair' ? 'lair' : 'bandit camp'} at (${camp.q}, ${camp.r})`;
  let ember = false;
  if (result.cleared) {
    await markCleared(client, camp.id);
    after = { ...after, loot: campLoot(data, camp.units) };
    ember = camp.kind === 'lair' && rngFor(world.seed, camp.id, 0xe3)() < data.camps.loot.emberChance;
    if (ember) await addEmbers(client, world.id, 1);
  } else {
    await saveCampUnits(client, camp.id, result.campNow);
  }
  if (hero) {
    await heroAfterBattle(
      client,
      data,
      world,
      result.cleared ? hero : { ...hero, villageId: army.homeVillageId, armyId: null },
      { kills, won: result.cleared, battleId: battle.id, at },
    );
  }
  await sendHome(client, world, after, at, data);
  await tell(client, world, army.ownerAccountId, {
    kind: 'battle_result',
    tier: 'digest',
    title: result.cleared ? `Your army cleared the ${where}` : `Your army was driven off from the ${where}`,
    body: result.cleared
      ? `It carries home ${total(campLoot(data, camp.units))} resources${ember ? " and a Svarog's Ember for the group" : ''}.`
      : `${kills} of them fell; ${total(result.campNow)} still hold it.`,
  }, at);
  await notifyWorld(client, { worldId: world.id, type: 'battles' });
  await notifyWorld(client, { worldId: world.id, type: 'world' });
}

// --- Caravan ambushes -------------------------------------------------------

async function scheduleAmbush(client: DbClient, world: World, payload: AmbushPayload, at: Date): Promise<void> {
  const { rows } = await client.query(
    `SELECT 1 FROM scheduled_events WHERE world_id = $1 AND type = 'caravan_ambush' AND status = 'pending' AND payload @> $2::jsonb`,
    [world.id, JSON.stringify({ caravanId: payload.caravanId, leg: payload.leg })],
  );
  if (rows.length) return;
  await scheduleEvent(client, world.id, at, 'caravan_ambush', payload);
}

function hasGoods(r: Resources | null): boolean {
  return !!r && Object.values(r).some((n) => n > 0);
}

// A caravan sets out (leg 'out') or turns for home ('back'): the first camp
// it passes close to ambushes it.
export async function planAmbushes(client: DbClient, data: GameData, world: World, caravan: Caravan, leg: 'out' | 'back', from: Date): Promise<void> {
  const goods = leg === 'out' ? caravan.cargo : caravan.carriedBack;
  if (!hasGoods(goods)) return;
  const travelMs = caravan.path.at(-1)!.atMs;
  let best: { campId: number; at: Date } | null = null;
  for (const camp of await listCamps(client, world.id)) {
    const cell = hex(camp.q, camp.r);
    const path = leg === 'out' ? caravan.path : [...caravan.path].reverse().map((s) => ({ ...s, atMs: travelMs - s.atMs }));
    const step = passesCamp(data, path, cell);
    if (!step) continue;
    const at = new Date((leg === 'out' ? caravan.departsAt : caravan.arrivesAt).getTime() + step.atMs);
    if (at < from) continue;
    if (!best || at < best.at) best = { campId: camp.id, at };
  }
  if (best) await scheduleAmbush(client, world, { caravanId: caravan.id, campId: best.campId, leg }, best.at);
}

// A new camp: caravans already on the road near it may be ambushed.
async function planAmbushesFor(client: DbClient, data: GameData, world: World, _camp: Camp, at: Date): Promise<void> {
  const { rows } = await client.query<{ id: number }>(`SELECT id FROM caravans WHERE world_id = $1 AND status <> 'done'`, [world.id]);
  for (const { id } of rows) {
    const caravan = await loadCaravan(client, id);
    if (caravan.ambush) continue;
    await planAmbushes(client, data, world, caravan, caravan.status === 'outbound' ? 'out' : 'back', at);
  }
}

// --- Abandoned forts --------------------------------------------------------

export async function planFortCheck(client: DbClient, data: GameData, world: World, fortId: number, from: Date): Promise<void> {
  await scheduleEvent(client, world.id, new Date(from.getTime() + hoursMs(data.camps.fort.abandonHours, world.speed)), 'fort_check', { fortId });
}

// The front whose bandits would take over a fort here.
function banditFront(world: World, cell: Hex): Front {
  const here = frontOf(cell);
  if (here !== 'north' && world.activeFronts.includes(here)) return here;
  return world.activeFronts.find((f) => f !== 'north') ?? world.activeFronts[0] ?? 'south';
}

export const campHandlers: HandlerRegistry = {
  async camp_grow({ client, data, world }, event) {
    const camp = await loadCamp(client, campPayload.parse(event.payload).campId);
    if (!camp || camp.status !== 'active') return;
    await saveCampUnits(client, camp.id, grow(data, camp.units));
    await scheduleEvent(client, world.id, new Date(event.dueAt.getTime() + hoursMs(data.camps.growth.everyHours, world.speed)), 'camp_grow', {
      campId: camp.id,
    });
    await notifyWorld(client, { worldId: world.id, type: 'world' });
  },

  async caravan_ambush({ client, data, world }, event) {
    const payload = ambushPayload.parse(event.payload);
    const caravan = await loadCaravan(client, payload.caravanId);
    const camp = await loadCamp(client, payload.campId);
    const expected = payload.leg === 'out' ? 'outbound' : 'returning';
    if (caravan.status !== expected || caravan.ambush || !camp || camp.status !== 'active') return;
    const goods = payload.leg === 'out' ? caravan.cargo : (caravan.carriedBack ?? emptyResources());
    const village = await loadVillage(client, caravan.villageId);
    const result = ambush(data, {
      escort: caravan.escort,
      escortStats: playerStats(data, village.state.bonuses, false),
      camp: camp.units,
      front: camp.front as Front,
      cargo: goods,
    });
    const left = mapResources((kind) => goods[kind] - result.lost[kind]);
    const escort: Record<string, number> = {};
    for (const [unit, n] of Object.entries(caravan.escort)) if (n - (result.escortLosses[unit] ?? 0) > 0) escort[unit] = n - (result.escortLosses[unit] ?? 0);
    if (Object.keys(result.escortLosses).length) {
      let state = village.state;
      for (const [unit, n] of Object.entries(result.escortLosses)) state = loseAway(data, state, unit, n, event.dueAt, world.speed);
      await saveVillageState(client, village.id, state);
      await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
    }
    await recordAmbush(
      client,
      caravan.id,
      { campId: camp.id, q: camp.q, r: camp.r, at: event.dueAt.toISOString(), beatenOff: result.beatenOff, lost: result.lost, escortLosses: result.escortLosses },
      payload.leg === 'out' ? left : caravan.cargo,
      payload.leg === 'back' ? left : caravan.carriedBack,
      escort,
    );
    await tell(client, world, village.ownerAccountId, {
      kind: 'ambush',
      tier: result.beatenOff ? 'digest' : 'push',
      title: result.beatenOff ? `A caravan from ${village.name} beat off an ambush` : `A caravan from ${village.name} was ambushed`,
      body: result.beatenOff
        ? `Its escort drove off the ${camp.kind === 'lair' ? 'beasts' : 'bandits'} at (${camp.q}, ${camp.r}).`
        : `It lost ${total(result.lost)} of its load near (${camp.q}, ${camp.r}).`,
    }, event.dueAt);
    await notifyWorld(client, { worldId: world.id, type: 'caravans' });
  },

  async fort_check({ client, data, world }, event) {
    const fort = await loadFort(client, fortCheckPayload.parse(event.payload).fortId);
    if (!fort || fort.status !== 'standing') return;
    const holders = await armiesHolding(client, world.id, fort.q, fort.r, ['stationed', 'engaged']);
    if (holders.length) {
      await markFortManned(client, fort.id, event.dueAt);
      await planFortCheck(client, data, world, fort.id, event.dueAt);
      return;
    }
    const since = fort.mannedAt ?? fort.completesAt;
    const abandonMs = hoursMs(data.camps.fort.abandonHours, world.speed);
    if (event.dueAt.getTime() - since.getTime() < abandonMs) {
      await scheduleEvent(client, world.id, new Date(since.getTime() + abandonMs), 'fort_check', { fortId: fort.id });
      return;
    }
    // Left empty too long: bandits move in.
    await deleteFort(client, fort.id);
    const front = banditFront(world, hex(fort.q, fort.r));
    const players = (await listMembers(client, world.id)).length;
    const units = composeWave(data, front, 0, data.camps.fort.units, world.seed ^ fort.id, players);
    await createCamp(client, data, world, { kind: 'bandit', front, q: fort.q, r: fort.r, units, waveId: null }, event.dueAt);
    await tell(client, world, fort.ownerAccountId, {
      kind: 'camp',
      tier: 'push',
      title: `Bandits took the fort at (${fort.q}, ${fort.r})`,
      body: 'No army held it, and now it is their camp. Send an army to clear it.',
    }, event.dueAt);
    await notifyWorld(client, { worldId: world.id, type: 'armies' });
  },
};

export async function deliverLoot(client: DbClient, world: World, army: Army, at: Date): Promise<void> {
  if (!army.loot) return;
  const home = await loadVillage(client, army.homeVillageId);
  const received = receive(home.state.ledger, at, army.loot);
  await saveVillageState(client, home.id, { ...home.state, ledger: received.ledger });
  await saveArmy(client, { ...army, loot: null });
  await notifyWorld(client, { worldId: world.id, type: 'village', villageId: home.id });
}
