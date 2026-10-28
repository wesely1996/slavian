// Field battles (PLAN.md §6.3) on the scheduler. An army holding a hex
// meets every horde whose road runs through it: field_intercept starts a
// battle there, with whatever the ground gives the holders (ambush, choke
// point, fort). Win, and the horde is beaten in the open; lose, and the
// holders fall back while the horde marches on, late. Forts are built
// from a village (fort_complete).
import { WATER } from '../sim/mapgen.js';
import { insertRoad, markRoadStanding, markRoadUpgrading, roadEdge, type RoadEdge } from '../db/roads.js';
import { canCross } from '../sim/land.js';
import { riverEdge, riverKeys, setCrossing, type StoredRiverEdge } from '../db/rivers.js';
import { againstFront } from '../sim/clans.js';
import { bonus } from '../sim/research.js';
import { z } from 'zod';
import type { GameData } from '../data/index.js';
import { armiesHolding, armiesInBattle, saveArmy, type Army } from '../db/armies.js';
import { insertBattle, recordRound, saveSetup, type Battle, type RoundLog } from '../db/battles.js';
import { fortAt, insertFort, loadFort, markFortStanding, type Fort, type FortKind } from '../db/forts.js';
import { campAt } from '../db/camps.js';
import { siteAt } from '../db/sites.js';
import { heroWithArmy, type Hero } from '../db/heroes.js';
import { generalWithArmy, type General } from '../db/generals.js';
import { generalBonuses } from '../sim/generals.js';
import { generalAfterBattle } from './generals.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { listVillages, loadVillage, saveVillageState } from '../db/villages.js';
import { listActiveWaves, loadWave, markBattling, resumeMarch, setWaveStrength, type Wave } from '../db/waves.js';
import { runLost } from './ritual.js';
import { damageSanctity, getWorld, listMembers, type World } from '../db/worlds.js';
import { RuleError } from '../errors.js';
import { addUnits, splitLosses } from '../sim/armies.js';
import { battleOutcome, battleRng, enemyStats, playerStats, resolveRound, roundMs, subtractUnits, total } from '../sim/battle.js';
import { cameOverRiver, setupAt, setupFactors, stepInto, type Setup } from '../sim/field.js';
import { sanctityDamage } from '../sim/horde.js';
import { combine, heroBonuses } from '../sim/heroes.js';
import { hex, hexDistance, type Hex } from '../sim/hex.js';
import { mapResources, spend, type Resources } from '../sim/resources.js';
import { outpostHex, outpostPlots } from '../sim/village.js';
import { armyLosses, sendHome, terrainOf } from './armies.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';
import { heroAfterBattle } from './heroes.js';
import { personality } from './battles.js';
import { hordeBeaten } from './horde.js';
import { hordeStats, leaderAfter } from './leaders.js';
import { finishWave, planFortCheck } from './camps.js';
import { holdForQuiet } from './waves.js';
import { bridgeQuest } from './bridge.js';
import { tell, tellOwner } from './notices.js';
import { planRaids, supplyPointPlaced } from './outposts.js';
import { record } from '../db/telemetry.js';

export const interceptPayload = z.object({ waveId: z.number().int(), q: z.number().int(), r: z.number().int(), atMs: z.number() });
export type InterceptPayload = z.infer<typeof interceptPayload>;
export const fortPayload = z.object({ fortId: z.number().int() });
export type FortPayload = z.infer<typeof fortPayload>;

// Schedules a field_intercept for when `wave` enters each held hex at or
// after `fromMs` into its march. The end of its road (a village or the
// Holy City) is left to the battle there.
async function scheduleIntercepts(client: DbClient, world: World, wave: Wave, cells: readonly Hex[], fromMs: number): Promise<void> {
  if (!wave.path) return;
  const end = wave.path.at(-1);
  for (const cell of cells) {
    if (end && end.q === cell.q && end.r === cell.r) continue;
    const step = stepInto(wave.path, cell, fromMs);
    if (!step) continue;
    const payload: InterceptPayload = { waveId: wave.id, q: cell.q, r: cell.r, atMs: step.atMs };
    const { rows } = await client.query(
      `SELECT 1 FROM scheduled_events WHERE world_id = $1 AND type = 'field_intercept' AND status = 'pending' AND payload @> $2::jsonb`,
      [world.id, JSON.stringify(payload)],
    );
    if (rows.length) continue;
    await scheduleEvent(client, world.id, new Date(wave.spawnAt.getTime() + step.atMs), 'field_intercept', payload);
  }
}

async function heldHexes(client: DbClient, worldId: number): Promise<Hex[]> {
  const { rows } = await client.query<{ q: number; r: number }>(
    `SELECT DISTINCT target_q AS q, target_r AS r FROM armies
     WHERE world_id = $1 AND orders = 'hold' AND target_village_id IS NULL AND status = 'stationed'`,
    [worldId],
  );
  return rows.map((row) => hex(row.q, row.r));
}

// A horde has (re)started its march: plan its run-ins with held hexes.
export async function planIntercepts(client: DbClient, world: World, waveId: number, fromMs = 0): Promise<void> {
  await scheduleIntercepts(client, world, await loadWave(client, waveId), await heldHexes(client, world.id), fromMs);
}

// An army has just taken up a hex: hordes still to pass it will meet it.
export async function interceptAt(client: DbClient, _data: GameData, world: World, cell: Hex, at: Date): Promise<void> {
  for (const wave of await listActiveWaves(client, world.id)) {
    if (wave.status !== 'marching') continue;
    await scheduleIntercepts(client, world, wave, [cell], at.getTime() - wave.spawnAt.getTime());
  }
}

// Drops a wave's pending raids and intercepts: its timetable has changed.
export async function cancelPlans(client: DbClient, worldId: number, waveId: number): Promise<void> {
  await client.query(
    `UPDATE scheduled_events SET status = 'done', processed_at = now(), error = 'superseded'
     WHERE world_id = $1 AND status = 'pending' AND type IN ('outpost_raid', 'supply_raid', 'field_intercept') AND payload @> $2::jsonb`,
    [worldId, JSON.stringify({ waveId })],
  );
}

// A standing fort (not a supply point) on the hex.
async function standingFort(client: DbClient, worldId: number, cell: Hex): Promise<Fort | null> {
  const fort = await fortAt(client, worldId, cell.q, cell.r);
  return fort?.status === 'standing' && fort.kind === 'fort' ? fort : null;
}

async function owners(armies: readonly Army[]): Promise<number[]> {
  return [...new Set(armies.map((a) => a.ownerAccountId).filter((id): id is number => id !== null))];
}

async function startFieldBattle(client: DbClient, data: GameData, world: World, wave: Wave, cell: Hex, at: Date): Promise<Battle | null> {
  const holders = await armiesHolding(client, world.id, cell.q, cell.r, ['stationed']);
  if (holders.length === 0) return null;
  const readySince = new Date(Math.min(...holders.map((a) => a.arrivesAt.getTime())));
  const setup: Setup = setupAt(data, {
    terrain: await terrainOf(client, world.id),
    cell,
    readySince,
    hordeArrives: at,
    worldSpeed: world.speed,
    fort: (await standingFort(client, world.id, cell)) !== null,
    river: cameOverRiver(wave.path ?? [], cell, await riverKeys(client, world.id)),
  });
  await markBattling(client, wave.id);
  const battle = await insertBattle(client, {
    worldId: world.id,
    waveId: wave.id,
    villageId: null,
    q: cell.q,
    r: cell.r,
    setup,
    attackerStance: wave.stance,
    attackerInitial: wave.composition,
    defenderInitial: holders.reduce<Record<string, number>>((sum, a) => addUnits(sum, a.units), {}),
    startedAt: at,
  });
  for (const army of holders) await saveArmy(client, { ...army, status: 'engaged', battleId: battle.id, joinsRound: 1, joinBonus: 0 });
  await scheduleEvent(client, world.id, new Date(at.getTime() + roundMs(data, world.speed)), 'battle_round', { battleId: battle.id });
  const ground = [setup.ambush && 'an ambush', setup.choke && 'a choke point', setup.fort && 'a fort', setup.river && 'a river crossing']
    .filter(Boolean)
    .join(', ');
  for (const owner of await owners(holders)) {
    await tell(client, world, owner, {
      kind: 'under_attack',
      tier: 'push',
      title: 'A horde ran into your army at ({q}, {r})',
      body: ground ? '{enemy} against {defenders}, with {ground}.' : '{enemy} against {defenders}.',
      vars: {
        q: cell.q,
        r: cell.r,
        enemy: total(wave.composition),
        defenders: total(battle.defenderInitial),
        ground,
      },
    }, at);
  }
  await notifyWorld(client, { worldId: world.id, type: 'armies' });
  await notifyWorld(client, { worldId: world.id, type: 'battles' });
  await notifyWorld(client, { worldId: world.id, type: 'waves' });
  return battle;
}

// One round of a field battle (battle_round for a battle with no village):
// on open ground, or at the Holy City, whose guard fights beside any armies
// holding it, behind its walls.
export async function fieldRound(client: DbClient, data: GameData, world: World, battle: Battle, at: Date): Promise<void> {
  const wave = await loadWave(client, battle.waveId!);
  const round = battle.round + 1;
  const engaged = await armiesInBattle(client, battle.id);
  const holy = battle.setup.holyCity === true;
  const guard = holy ? (battle.setup.guard ?? {}) : null;
  const leader = engaged[0] ? await loadVillage(client, engaged[0].homeVillageId) : null;
  const stance = holy ? data.horde.holyCity.stance : (leader?.state.stance ?? 'balanced');
  // The holders fight with their owner's research and the hero leading them.
  let hero: Hero | null = null;
  for (const army of engaged) hero ??= await heroWithArmy(client, army.id);
  // And the best general among them.
  let general: General | null = null;
  for (const army of engaged) {
    const g = await generalWithArmy(client, army.id);
    if (g && (!general || g.level > general.level)) general = g;
  }
  const research = againstFront(leader?.state.bonuses ?? {}, wave.front);
  const heroic = hero ? combine(research, heroBonuses(data, hero)) : research;
  const bonuses = general ? combine(heroic, generalBonuses(data, general)) : heroic;
  const ground: Setup = { ambush: !!battle.setup.ambush, choke: !!battle.setup.choke, fort: !!battle.setup.fort, river: !!battle.setup.river };
  const factors = setupFactors(data, ground, { round, holdersStance: stance, ambushBonus: bonus(bonuses, 'ambush') });
  const forces = [...(guard ? [guard] : []), ...engaged.map((a) => a.units)];
  const holderBase = playerStats(data, bonuses, false);
  const chief = await hordeStats(client, data, wave, enemyStats(data, wave.front), null);
  const hordeBase = chief.stats;
  const result = resolveRound(
    data,
    {
      units: wave.composition,
      // Caught by surprise, the horde can't keep its formation.
      stance: factors.hordeStanceless ? 'balanced' : battle.attackerStance,
      stats: (unit) => ({ ...hordeBase(unit), attack: hordeBase(unit).attack * factors.hordeAttack }),
      home: false,
    },
    {
      units: forces.reduce<Record<string, number>>((sum, f) => addUnits(sum, f), {}),
      stance,
      stats: (unit) => ({
        ...holderBase(unit),
        attack: holderBase(unit).attack * factors.holderAttack,
        defense: holderBase(unit).defense * factors.holderDefense,
      }),
      home: holy,
    },
    battleRng(world.seed, battle.id, round),
  );
  const attackerNow = subtractUnits(wave.composition, result.attackerLosses);
  await setWaveStrength(client, wave.id, attackerNow);
  const shares = splitLosses(result.defenderLosses, forces);
  const guardNow = guard ? subtractUnits(guard, shares[0]!) : null;
  if (guardNow) await saveSetup(client, battle.id, { ...battle.setup, guard: guardNow });
  const offset = guard ? 1 : 0;
  const armies: Army[] = [];
  for (const [i, army] of engaged.entries()) armies.push(await armyLosses(client, data, world, army, shares[i + offset]!, at));
  const defendersNow = armies.reduce<Record<string, number>>((sum, a) => addUnits(sum, a.units), { ...(guardNow ?? {}) });

  const outcome = battleOutcome(data, {
    round,
    attackerStance: battle.attackerStance,
    attackerInitial: battle.attackerInitial,
    attackerNow,
    defenderStance: stance,
    defenderInitial: battle.defenderInitial,
    defenderNow: defendersNow,
    attackerNerve: personality(data, wave).nerve * (1 + chief.nerve),
  });
  const log: RoundLog = {
    round,
    at: at.toISOString(),
    attackerLosses: result.attackerLosses,
    defenderLosses: result.defenderLosses,
    attackerLeft: total(attackerNow),
    defenderLeft: total(defendersNow),
  };

  if (outcome === 'ongoing') {
    for (const army of armies) await saveArmy(client, total(army.units) ? army : { ...army, status: 'done' });
    await recordRound(client, battle.id, log, null);
    await scheduleEvent(client, world.id, new Date(at.getTime() + roundMs(data, world.speed)), 'battle_round', { battleId: battle.id });
  } else {
    const won = outcome === 'defended';
    const kills = total(battle.attackerInitial) - total(attackerNow);
    await record(client, world.id, 'wave_result', {
      wave: wave.index,
      front: wave.front,
      threat: wave.threat,
      where: holy ? 'holy_city' : 'field',
      outcome: won ? 'held' : 'broke',
      rounds: round,
      horde: total(battle.attackerInitial),
      defenders: total(battle.defenderInitial),
    }, at);
    // Beaten in the field, the horde's leader blames the army's village.
    const fallen = total(result.defenderLosses) + battle.rounds.reduce((n, r) => n + total(r.defenderLosses), 0);
    await leaderAfter(client, data, world, wave, { hordeWon: !won, kills: fallen, wiped: total(attackerNow) === 0, villageId: leader?.id ?? null }, at);
    // Heroes first: a beaten hero is carried home wounded.
    for (const army of armies) {
      const led = await heroWithArmy(client, army.id);
      if (!led) continue;
      await heroAfterBattle(client, data, world, won ? led : { ...led, villageId: army.homeVillageId, armyId: null }, { kills, won, battleId: battle.id, at });
    }
    for (const army of armies) {
      const commander = await generalWithArmy(client, army.id);
      if (commander) await generalAfterBattle(client, data, world, commander, { kills, won, at });
    }
    for (const army of armies) {
      if (won && total(army.units)) await saveArmy(client, { ...army, status: 'stationed', battleId: null, joinsRound: null, joinBonus: 0 });
      else await sendHome(client, world, army, at, data);
    }
    await recordRound(client, battle.id, log, { status: won ? 'defended' : 'raided', at, loot: null });
    if (won) {
      await hordeBeaten(client, data, world, hex(battle.q, battle.r), kills);
      await finishWave(client, data, world, wave.id, 'defeated', at);
      // A strong point held: a choke, or a fort built on the horde's road.
      if (battle.setup.choke || battle.setup.fort) await bridgeQuest(client, data, world, 'choke', at);
    } else if (holy) {
      await holyCityFalls(client, data, world, wave, attackerNow, at);
    } else {
      await marchOn(client, data, world, wave, hex(battle.q, battle.r), at);
    }
    if (holy) {
      for (const member of await listMembers(client, world.id)) {
        await tell(client, world, member.accountId, {
          kind: 'battle_result',
          tier: won ? 'digest' : 'push',
          title: won ? 'The Holy City held' : 'The Holy City was struck',
          body: won ? 'The horde was beaten at its walls after {rounds} rounds.' : 'Its Sanctity fell to {sanctity}.',
          vars: won ? { rounds: round } : { sanctity: (await getWorld(client, world.id)).sanctity },
        }, at);
      }
    }
    for (const owner of holy ? [] : await owners(engaged)) {
      await tell(client, world, owner, {
        kind: 'battle_result',
        tier: 'digest',
        title: won ? 'Your army held ({q}, {r})' : 'Your army fell back from ({q}, {r})',
        body: won ? 'The horde was beaten after {rounds} rounds.' : 'The horde marches on, {rounds} rounds late.',
        vars: { q: battle.q, r: battle.r, rounds: round },
      }, at);
    }
    await notifyWorld(client, { worldId: world.id, type: 'waves' });
  }
  await notifyWorld(client, { worldId: world.id, type: 'armies' });
  await notifyWorld(client, { worldId: world.id, type: 'battles' });
}

// A horde beat the Holy City's defenders: Sanctity falls by its survivors,
// and the horde, its rampage done, scatters.
async function holyCityFalls(client: DbClient, data: GameData, world: World, wave: Wave, survivors: Record<string, number>, at: Date): Promise<void> {
  const sanctity = await damageSanctity(client, world.id, sanctityDamage(data, total(survivors)), at);
  await finishWave(client, data, world, wave.id, 'dispersed', at);
  if (sanctity <= 0) await runLost(client, data, world, at, wave.front);
  await notifyWorld(client, { worldId: world.id, type: 'world' });
}

// The horde broke through: the rest of its road shifts by the time it spent
// fighting, and its raids and later intercepts are planned again.
async function marchOn(client: DbClient, data: GameData, world: World, wave: Wave, cell: Hex, at: Date): Promise<void> {
  const path = wave.path ?? [];
  const sinceSpawn = at.getTime() - wave.spawnAt.getTime();
  const step = [...path].reverse().find((s) => s.q === cell.q && s.r === cell.r && s.atMs <= sinceSpawn);
  const delay = step ? Math.max(0, sinceSpawn - step.atMs) : 0;
  const late = holdForQuiet(world, wave.spawnAt, {
    path: path.map((s) => (step && s.atMs > step.atMs ? { ...s, atMs: s.atMs + delay } : s)),
    arrivesAt: new Date((wave.arrivesAt ?? at).getTime() + delay),
  });
  const arrivesAt = late.arrivesAt;
  await resumeMarch(client, wave.id, [...late.path], arrivesAt);
  await cancelPlans(client, world.id, wave.id);
  await scheduleEvent(client, world.id, arrivesAt, 'wave_arrive', { waveId: wave.id });
  await planRaids(client, data, world, wave.id, sinceSpawn);
  await planIntercepts(client, world, wave.id, sinceSpawn + 1);
}

// What a fort costs its builder (some clans pay more, some less).
export function fortCost(data: GameData, bonuses: Record<string, number>): Resources {
  const factor = Math.max(0.1, 1 + bonus(bonuses, 'fortCost'));
  return mapResources((kind) => Math.round(data.field.fort.cost[kind] * factor));
}

// Builds a fort (or a supply point) on a hex near the village, paid from its stores.
export async function buildFort(client: DbClient, data: GameData, world: World, villageId: number, cell: Hex, at: Date, kind: FortKind = 'fort'): Promise<Fort> {
  const rules = kind === 'supply' ? data.field.supplyPoint : data.field.fort;
  const what = kind === 'supply' ? 'supply point' : 'fort';
  const village = await loadVillage(client, villageId);
  const distance = hexDistance(cell, hex(village.q, village.r));
  if (distance === 0 || distance > rules.range) throw new RuleError(kind === 'supply' ? `Supply points go within ${rules.range} hexes of the village` : `Forts go within ${rules.range} hexes of the village`);
  const terrain = (await terrainOf(client, world.id)).get(`${cell.q},${cell.r}`);
  if (!terrain || terrain === 'holy_city' || data.terrain.terrain[terrain].moveCost === null) throw new RuleError(`No ${what} can stand there`);
  const villages = await listVillages(client, world.id);
  if (villages.some((v) => v.q === cell.q && v.r === cell.r)) throw new RuleError('There is a village there');
  const outposts = villages.flatMap((v) => outpostPlots(v.state.plots).map((plot) => outpostHex(plot)!));
  if (outposts.some((o) => o.q === cell.q && o.r === cell.r)) throw new RuleError('There is an outpost there');
  const there = await fortAt(client, world.id, cell.q, cell.r);
  if (there) throw new RuleError(there.kind === 'supply' ? 'There is a supply point there already' : 'There is a fort there already');
  if (await campAt(client, world.id, cell.q, cell.r)) throw new RuleError('A camp stands there; clear it first');
  if ((await siteAt(client, world.id, cell.q, cell.r))?.status === 'unexplored') throw new RuleError('An ancient site lies there');
  const cost = kind === 'supply' ? data.field.supplyPoint.cost : fortCost(data, village.state.bonuses);
  await saveVillageState(client, village.id, { ...village.state, ledger: spend(village.state.ledger, at, cost) });
  const fort = await insertFort(client, {
    kind,
    worldId: world.id,
    ownerAccountId: village.ownerAccountId,
    villageId: village.id,
    q: cell.q,
    r: cell.r,
    completesAt: new Date(at.getTime() + (rules.buildSeconds * 1000) / world.speed),
  });
  const payload: FortPayload = { fortId: fort.id };
  await scheduleEvent(client, world.id, fort.completesAt, 'fort_complete', payload);
  // Hordes on the march may pass it and burn it.
  if (kind === 'supply') await supplyPointPlaced(client, data, world, fort, at);
  await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
  await notifyWorld(client, { worldId: world.id, type: 'armies' });
  return fort;
}

export const crossingPayload = z.object({ aq: z.number().int(), ar: z.number().int(), bq: z.number().int(), br: z.number().int() });

// Builds a bridge over a river edge near the village, paid from its stores.
export async function buildCrossing(client: DbClient, data: GameData, world: World, villageId: number, a: Hex, b: Hex, at: Date): Promise<StoredRiverEdge> {
  const rules = data.field.bridge;
  const village = await loadVillage(client, villageId);
  const home = hex(village.q, village.r);
  if (Math.min(hexDistance(a, home), hexDistance(b, home)) > rules.range) throw new RuleError(`Bridges go within ${rules.range} hexes of the village`);
  const edge = await riverEdge(client, world.id, a, b);
  if (!edge) throw new RuleError('No river runs there');
  // Old maps had rivers along lake shores; a bridge needs land on both banks.
  const land = await terrainOf(client, world.id);
  if ([a, b].some((end) => WATER.includes(land.get(`${end.q},${end.r}`) ?? ''))) throw new RuleError('A bridge needs land on both banks');
  if (edge.crossing !== 'none') throw new RuleError(edge.crossing === 'standing' ? 'A bridge already stands there' : 'A bridge is being built there');
  await saveVillageState(client, village.id, { ...village.state, ledger: spend(village.state.ledger, at, rules.cost) });
  const completesAt = new Date(at.getTime() + (rules.buildSeconds * 1000) / world.speed);
  await setCrossing(client, world.id, a, b, 'building', village.id, completesAt);
  await scheduleEvent(client, world.id, completesAt, 'crossing_built', { aq: a.q, ar: a.r, bq: b.q, br: b.r });
  await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
  await notifyWorld(client, { worldId: world.id, type: 'world' });
  return (await riverEdge(client, world.id, a, b))!;
}

// Builds a road between two neighbouring hexes near the village, or
// improves the standing road there to its next level.
export async function buildRoad(client: DbClient, data: GameData, world: World, villageId: number, a: Hex, b: Hex, at: Date): Promise<RoadEdge> {
  const rules = data.field.road;
  const village = await loadVillage(client, villageId);
  const home = hex(village.q, village.r);
  if (hexDistance(a, b) !== 1) throw new RuleError('A road joins two neighbouring hexes');
  if (Math.min(hexDistance(a, home), hexDistance(b, home)) > rules.range) throw new RuleError(`Roads go within ${rules.range} hexes of the village`);
  const land = await terrainOf(client, world.id);
  for (const end of [a, b]) {
    const type = land.get(`${end.q},${end.r}`);
    if (!type || data.terrain.terrain[type].moveCost === null) throw new RuleError('No road can run there');
  }
  if (!canCross(land, a, b)) throw new RuleError('A river lies between; build a bridge first');
  const existing = await roadEdge(client, world.id, a, b);
  if (existing?.status === 'building') throw new RuleError('A road is being built there');
  if (existing?.status === 'upgrading') throw new RuleError('That road is being improved');
  if (existing && existing.level >= rules.levels.length) throw new RuleError('That road is as good as it gets');
  const level = rules.levels[existing ? existing.level : 0]!;
  await saveVillageState(client, village.id, { ...village.state, ledger: spend(village.state.ledger, at, level.cost) });
  const completesAt = new Date(at.getTime() + (level.buildSeconds * 1000) / world.speed);
  if (existing) await markRoadUpgrading(client, world.id, a, b, village.id, completesAt);
  else await insertRoad(client, world.id, a, b, village.id, completesAt);
  await scheduleEvent(client, world.id, completesAt, 'road_built', { aq: a.q, ar: a.r, bq: b.q, br: b.r });
  await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
  await notifyWorld(client, { worldId: world.id, type: 'world' });
  return (await roadEdge(client, world.id, a, b))!;
}

export const fieldHandlers: HandlerRegistry = {
  async road_built({ client, world }, event) {
    const { aq, ar, bq, br } = crossingPayload.parse(event.payload);
    const road = await roadEdge(client, world.id, hex(aq, ar), hex(bq, br));
    if (!road || road.status === 'standing') return;
    await markRoadStanding(client, world.id, road.a, road.b, road.status === 'upgrading' ? road.level + 1 : road.level);
    await notifyWorld(client, { worldId: world.id, type: 'world' });
  },

  // A bridge stands: from now on, roads (and hordes) may cross there.
  async crossing_built({ client, world }, event) {
    const { aq, ar, bq, br } = crossingPayload.parse(event.payload);
    const edge = await riverEdge(client, world.id, hex(aq, ar), hex(bq, br));
    if (!edge || edge.crossing !== 'building') return;
    await setCrossing(client, world.id, edge.a, edge.b, 'standing', null, null);
    if (edge.builtBy !== null) {
      await tellOwner(client, world, edge.builtBy, (name) => ({
        kind: 'build_done',
        tier: 'digest',
        title: 'A bridge stands near {village}',
        body: 'Roads now cross the river between ({aq}, {ar}) and ({bq}, {br}), for friend and foe alike.',
        vars: { village: name, aq, ar, bq, br },
      }), event.dueAt);
    }
    await notifyWorld(client, { worldId: world.id, type: 'world' });
  },

  async field_intercept({ client, data, world }, event) {
    const payload = interceptPayload.parse(event.payload);
    const wave = await loadWave(client, payload.waveId);
    if (wave.status !== 'marching' || !wave.path?.some((s) => s.q === payload.q && s.r === payload.r && s.atMs === payload.atMs)) return;
    await startFieldBattle(client, data, world, wave, hex(payload.q, payload.r), event.dueAt);
  },

  async fort_complete({ client, data, world }, event) {
    const fort = await loadFort(client, fortPayload.parse(event.payload).fortId);
    if (!fort || fort.status !== 'building') return;
    await markFortStanding(client, fort.id);
    if (fort.kind === 'supply') {
      await tell(client, world, fort.ownerAccountId, {
        kind: 'build_done',
        tier: 'digest',
        title: 'Supply point at ({q}, {r}) finished',
        body: 'Armies standing there fill up from its grain; supply routes keep it stocked.',
        vars: { q: fort.q, r: fort.r },
      }, event.dueAt);
      await notifyWorld(client, { worldId: world.id, type: 'armies' });
      return;
    }
    await planFortCheck(client, data, world, fort.id, event.dueAt);
    await tell(client, world, fort.ownerAccountId, {
      kind: 'build_done',
      tier: 'digest',
      title: 'Fort at ({q}, {r}) finished',
      body: 'Armies holding it fight from behind its walls.',
      vars: { q: fort.q, r: fort.r },
    }, event.dueAt);
    await notifyWorld(client, { worldId: world.id, type: 'armies' });
  },
};
