// Field battles (PLAN.md §6.3) on the scheduler. An army holding a hex
// meets every horde whose road runs through it: field_intercept starts a
// battle there, with whatever the ground gives the holders (ambush, choke
// point, fort). Win, and the horde is beaten in the open; lose, and the
// holders fall back while the horde marches on, late. Forts are built
// from a village (fort_complete).
import { z } from 'zod';
import type { GameData } from '../data/index.js';
import { armiesHolding, armiesInBattle, saveArmy, type Army } from '../db/armies.js';
import { insertBattle, recordRound, type Battle, type RoundLog } from '../db/battles.js';
import { fortAt, insertFort, loadFort, markFortStanding, type Fort } from '../db/forts.js';
import { heroWithArmy, type Hero } from '../db/heroes.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { listVillages, loadVillage, saveVillageState } from '../db/villages.js';
import { endWave, listActiveWaves, loadWave, markBattling, resumeMarch, setWaveStrength, type Wave } from '../db/waves.js';
import type { World } from '../db/worlds.js';
import { RuleError } from '../errors.js';
import { addUnits, splitLosses } from '../sim/armies.js';
import { battleOutcome, battleRng, enemyStats, playerStats, resolveRound, roundMs, subtractUnits, total } from '../sim/battle.js';
import { setupAt, setupFactors, stepInto, type Setup } from '../sim/field.js';
import { combine, heroBonuses } from '../sim/heroes.js';
import { hex, hexDistance, type Hex } from '../sim/hex.js';
import { spend } from '../sim/resources.js';
import { outpostHex, outpostPlots } from '../sim/village.js';
import { armyLosses, sendHome, terrainOf } from './armies.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';
import { heroAfterBattle } from './heroes.js';
import { personality } from './battles.js';
import { tell } from './notices.js';
import { planRaids } from './outposts.js';

export const interceptPayload = z.object({ waveId: z.number().int(), q: z.number().int(), r: z.number().int(), atMs: z.number() });
export type InterceptPayload = z.infer<typeof interceptPayload>;
export const fortPayload = z.object({ fortId: z.number().int() });
export type FortPayload = z.infer<typeof fortPayload>;

// Schedules a field_intercept for when `wave` enters each held hex at or
// after `fromMs` into its march. Its target village's own hex is left to
// the village battle.
async function scheduleIntercepts(client: DbClient, world: World, wave: Wave, cells: readonly Hex[], fromMs: number): Promise<void> {
  if (!wave.path) return;
  const end = wave.path.at(-1);
  for (const cell of cells) {
    if (wave.targetVillageId !== null && end && end.q === cell.q && end.r === cell.r) continue;
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
async function cancelPlans(client: DbClient, worldId: number, waveId: number): Promise<void> {
  await client.query(
    `UPDATE scheduled_events SET status = 'done', processed_at = now(), error = 'superseded'
     WHERE world_id = $1 AND status = 'pending' AND type IN ('outpost_raid', 'field_intercept') AND payload @> $2::jsonb`,
    [worldId, JSON.stringify({ waveId })],
  );
}

async function standingFort(client: DbClient, worldId: number, cell: Hex): Promise<Fort | null> {
  const fort = await fortAt(client, worldId, cell.q, cell.r);
  return fort?.status === 'standing' ? fort : null;
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
  const ground = [setup.ambush && 'an ambush', setup.choke && 'a choke point', setup.fort && 'a fort'].filter(Boolean).join(', ');
  for (const owner of await owners(holders)) {
    await tell(client, world, owner, {
      kind: 'under_attack',
      tier: 'push',
      title: `A horde ran into your army at (${cell.q}, ${cell.r})`,
      body: `${total(wave.composition)} against ${total(battle.defenderInitial)}${ground ? `, with ${ground}` : ''}.`,
    }, at);
  }
  await notifyWorld(client, { worldId: world.id, type: 'armies' });
  await notifyWorld(client, { worldId: world.id, type: 'battles' });
  await notifyWorld(client, { worldId: world.id, type: 'waves' });
  return battle;
}

// One round of a field battle (battle_round for a battle with no village).
export async function fieldRound(client: DbClient, data: GameData, world: World, battle: Battle, at: Date): Promise<void> {
  const wave = await loadWave(client, battle.waveId);
  const round = battle.round + 1;
  const engaged = await armiesInBattle(client, battle.id);
  const leader = engaged[0] ? await loadVillage(client, engaged[0].homeVillageId) : null;
  const stance = leader?.state.stance ?? 'balanced';
  // The holders fight with their owner's research and the hero leading them.
  let hero: Hero | null = null;
  for (const army of engaged) hero ??= await heroWithArmy(client, army.id);
  const research = leader?.state.bonuses ?? {};
  const bonuses = hero ? combine(research, heroBonuses(data, hero)) : research;
  const factors = setupFactors(data, battle.setup as Setup, { round, holdersStance: stance });
  const holderBase = playerStats(data, bonuses, false);
  const hordeBase = enemyStats(data, wave.front);
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
      units: engaged.reduce<Record<string, number>>((sum, a) => addUnits(sum, a.units), {}),
      stance,
      stats: (unit) => ({
        ...holderBase(unit),
        attack: holderBase(unit).attack * factors.holderAttack,
        defense: holderBase(unit).defense * factors.holderDefense,
      }),
      home: false,
    },
    battleRng(world.seed, battle.id, round),
  );
  const attackerNow = subtractUnits(wave.composition, result.attackerLosses);
  await setWaveStrength(client, wave.id, attackerNow);
  const shares = splitLosses(result.defenderLosses, engaged.map((a) => a.units));
  const armies: Army[] = [];
  for (const [i, army] of engaged.entries()) armies.push(await armyLosses(client, data, world, army, shares[i]!, at));
  const defendersNow = armies.reduce<Record<string, number>>((sum, a) => addUnits(sum, a.units), {});

  const outcome = battleOutcome(data, {
    round,
    attackerStance: battle.attackerStance,
    attackerInitial: battle.attackerInitial,
    attackerNow,
    defenderStance: stance,
    defenderInitial: battle.defenderInitial,
    defenderNow: defendersNow,
    attackerNerve: personality(data, wave).nerve,
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
    // Heroes first: a beaten hero is carried home wounded.
    for (const army of armies) {
      const led = await heroWithArmy(client, army.id);
      if (!led) continue;
      await heroAfterBattle(client, data, world, won ? led : { ...led, villageId: army.homeVillageId, armyId: null }, { kills, won, battleId: battle.id, at });
    }
    for (const army of armies) {
      if (won && total(army.units)) await saveArmy(client, { ...army, status: 'stationed', battleId: null, joinsRound: null, joinBonus: 0 });
      else await sendHome(client, world, army, at, data);
    }
    await recordRound(client, battle.id, log, { status: won ? 'defended' : 'raided', at, loot: null });
    if (won) await endWave(client, wave.id, 'defeated', at);
    else await marchOn(client, data, world, wave, hex(battle.q, battle.r), at);
    for (const owner of await owners(engaged)) {
      await tell(client, world, owner, {
        kind: 'battle_result',
        tier: 'digest',
        title: won ? `Your army held (${battle.q}, ${battle.r})` : `Your army fell back from (${battle.q}, ${battle.r})`,
        body: won ? `The horde was beaten after ${round} rounds.` : `The horde marches on, ${round} rounds late.`,
      }, at);
    }
    await notifyWorld(client, { worldId: world.id, type: 'waves' });
  }
  await notifyWorld(client, { worldId: world.id, type: 'armies' });
  await notifyWorld(client, { worldId: world.id, type: 'battles' });
}

// The horde broke through: the rest of its road shifts by the time it spent
// fighting, and its raids and later intercepts are planned again.
async function marchOn(client: DbClient, data: GameData, world: World, wave: Wave, cell: Hex, at: Date): Promise<void> {
  const path = wave.path ?? [];
  const sinceSpawn = at.getTime() - wave.spawnAt.getTime();
  const step = [...path].reverse().find((s) => s.q === cell.q && s.r === cell.r && s.atMs <= sinceSpawn);
  const delay = step ? Math.max(0, sinceSpawn - step.atMs) : 0;
  const shifted = path.map((s) => (step && s.atMs > step.atMs ? { ...s, atMs: s.atMs + delay } : s));
  const arrivesAt = new Date((wave.arrivesAt ?? at).getTime() + delay);
  await resumeMarch(client, wave.id, shifted, arrivesAt);
  await cancelPlans(client, world.id, wave.id);
  await scheduleEvent(client, world.id, arrivesAt, 'wave_arrive', { waveId: wave.id });
  await planRaids(client, data, world, wave.id, sinceSpawn);
  await planIntercepts(client, world, wave.id, sinceSpawn + 1);
}

// Builds a fort on a hex near the village, paid from its stores.
export async function buildFort(client: DbClient, data: GameData, world: World, villageId: number, cell: Hex, at: Date): Promise<Fort> {
  const rules = data.field.fort;
  const village = await loadVillage(client, villageId);
  const distance = hexDistance(cell, hex(village.q, village.r));
  if (distance === 0 || distance > rules.range) throw new RuleError(`Forts go within ${rules.range} hexes of the village`);
  const terrain = (await terrainOf(client, world.id)).get(`${cell.q},${cell.r}`);
  if (!terrain || terrain === 'holy_city' || data.terrain.terrain[terrain].moveCost === null) throw new RuleError('No fort can stand there');
  const villages = await listVillages(client, world.id);
  if (villages.some((v) => v.q === cell.q && v.r === cell.r)) throw new RuleError('There is a village there');
  const outposts = villages.flatMap((v) => outpostPlots(v.state.plots).map((plot) => outpostHex(plot)!));
  if (outposts.some((o) => o.q === cell.q && o.r === cell.r)) throw new RuleError('There is an outpost there');
  if (await fortAt(client, world.id, cell.q, cell.r)) throw new RuleError('There is a fort there already');
  await saveVillageState(client, village.id, { ...village.state, ledger: spend(village.state.ledger, at, rules.cost) });
  const fort = await insertFort(client, {
    worldId: world.id,
    ownerAccountId: village.ownerAccountId,
    villageId: village.id,
    q: cell.q,
    r: cell.r,
    completesAt: new Date(at.getTime() + (rules.buildSeconds * 1000) / world.speed),
  });
  const payload: FortPayload = { fortId: fort.id };
  await scheduleEvent(client, world.id, fort.completesAt, 'fort_complete', payload);
  await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
  await notifyWorld(client, { worldId: world.id, type: 'armies' });
  return fort;
}

export const fieldHandlers: HandlerRegistry = {
  async field_intercept({ client, data, world }, event) {
    const payload = interceptPayload.parse(event.payload);
    const wave = await loadWave(client, payload.waveId);
    if (wave.status !== 'marching' || !wave.path?.some((s) => s.q === payload.q && s.r === payload.r && s.atMs === payload.atMs)) return;
    await startFieldBattle(client, data, world, wave, hex(payload.q, payload.r), event.dueAt);
  },

  async fort_complete({ client, world }, event) {
    const fort = await loadFort(client, fortPayload.parse(event.payload).fortId);
    if (!fort || fort.status !== 'building') return;
    await markFortStanding(client, fort.id);
    await tell(client, world, fort.ownerAccountId, {
      kind: 'build_done',
      tier: 'digest',
      title: `Fort at (${fort.q}, ${fort.r}) finished`,
      body: 'Armies holding it fight from behind its walls.',
    }, event.dueAt);
    await notifyWorld(client, { worldId: world.id, type: 'armies' });
  },
};
