// The horde AI on the scheduler (PLAN.md §7.3): after beating a village a
// horde raids or razes it (wave_raze), then moves on to the next village it
// hasn't struck until its rampage clock runs out and its survivors settle
// into a bandit camp. Razed villages are ruins until rebuilt
// (village_rebuilt); a player left with only ruins gets a refugee camp. A
// horde reaching the Holy City fights its guard there (see field.ts).
import { z } from 'zod';
import type { GameData } from '../data/index.js';
import { listArmies, loadReinforceRule, saveArmy } from '../db/armies.js';
import { insertBattle, type Battle } from '../db/battles.js';
import { listCamps } from '../db/camps.js';
import { listSites } from '../db/sites.js';
import { afterSettling, createCamp, finishWave } from './camps.js';
import { addFear } from '../db/fear.js';
import { presetOf } from '../sim/difficulty.js';
import { fearOf, holdForQuiet } from './waves.js';
import { playerBonuses } from './research.js';
import { listForts } from '../db/forts.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { insertVillage, listVillages, loadVillage, markRefuge, saveRuin, saveVillageState, type Village } from '../db/villages.js';
import {
  loadWave,
  markBattling,
  markRazing,
  markSettled,
  markStruck,
  marchOnward,
  setWaveStrength,
  startRampage,
  type Wave,
} from '../db/waves.js';
import { listMembers, type World } from '../db/worlds.js';
import { fighters, total } from '../sim/armies.js';
import { roundMs } from '../sim/battle.js';
import {
  campSite,
  decideRaze,
  fearLeft,
  holyCityGuard,
  razeMs,
  rebuildMs,
  recruit,
  refugeeSite,
  ruinPlots,
  type Decision,
} from '../sim/horde.js';
import { hex, hexDistance, hexKey, type Hex } from '../sim/hex.js';
import { capacity, levelsOf, newVillage, outpostHex, outpostPlots, villageRates, type VillageState } from '../sim/village.js';
import { withRates } from '../sim/resources.js';
import { rngFor, routeFrom, targetsOf } from '../sim/waves.js';
import { terrainOf } from './armies.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';
import { cancelPlans, planIntercepts } from './field.js';
import { planWaveWarning, tell } from './notices.js';
import { planRaids } from './outposts.js';

const MS_PER_HOUR = 3_600_000;

export const razePayload = z.object({ waveId: z.number().int(), villageId: z.number().int() });
export type RazePayload = z.infer<typeof razePayload>;
export const rebuildPayload = z.object({ villageId: z.number().int() });
export type RebuildPayload = z.infer<typeof rebuildPayload>;

// The horde reached a target: its rampage clock starts (once).
export async function beginRampage(client: DbClient, data: GameData, world: World, wave: Wave, at: Date): Promise<void> {
  await startRampage(client, wave.id, new Date(at.getTime() + (data.horde.rampageHours * MS_PER_HOUR) / world.speed));
}

// A horde was beaten here: hordes remember.
export async function hordeBeaten(client: DbClient, data: GameData, world: World, cell: Hex, killed: number): Promise<void> {
  await addFear(client, world.id, cell.q, cell.r, fearLeft(data, killed));
}

// Troops that could reach `village` in time: every other standing village
// whose reinforce rule covers it.
async function helpNearby(client: DbClient, data: GameData, world: World, village: Village): Promise<number> {
  let help = 0;
  for (const other of await listVillages(client, world.id)) {
    if (other.id === village.id || other.ruin || other.state.besieged) continue;
    const rule = other.reinforce ?? (await loadReinforceRule(client, other.id));
    if (rule.share <= 0 || hexDistance(hex(other.q, other.r), hex(village.q, village.r)) > rule.range) continue;
    help += Math.floor(total(fighters(data, other.state.garrison)) * rule.share);
  }
  return help;
}

// The horde beat the village's defenders: raid or raze? Returns the
// decision; for a raid the caller takes the loot and the horde moves on.
export async function hordeWins(
  client: DbClient,
  data: GameData,
  world: World,
  wave: Wave,
  village: Village,
  attackerNow: Record<string, number>,
  at: Date,
): Promise<Decision> {
  const fresh = await loadWave(client, wave.id);
  const rampageLeftMs = (fresh.rampageEndsAt?.getTime() ?? at.getTime()) - at.getTime();
  const preset = presetOf(data, world.difficulty);
  const decision = decideRaze(data, {
    front: wave.front,
    waveIndex: wave.index,
    graceWaves: preset.graceWaves,
    thresholdOffset: preset.razeThreshold,
    refuge: village.refuge === true,
    hordeNow: total(attackerNow),
    hordeInitial: total(fresh.initial),
    helpNearby: await helpNearby(client, data, world, village),
    rampageLeftMs,
    worldSpeed: world.speed,
  });
  await markStruck(client, wave.id, village.id);
  if (decision.choice === 'raze') {
    const endsAt = new Date(at.getTime() + razeMs(data, world.speed));
    await markRazing(client, wave.id, endsAt);
    const payload: RazePayload = { waveId: wave.id, villageId: village.id };
    await scheduleEvent(client, world.id, endsAt, 'wave_raze', payload);
  } else {
    await setWaveStrength(client, wave.id, recruit(data, fresh.initial, attackerNow));
  }
  return decision;
}

async function takenHexes(client: DbClient, worldId: number): Promise<Set<string>> {
  const taken = new Set<string>();
  for (const v of await listVillages(client, worldId)) {
    taken.add(hexKey(hex(v.q, v.r)));
    for (const plot of outpostPlots(v.state.plots)) taken.add(hexKey(outpostHex(plot)!));
  }
  for (const f of await listForts(client, worldId)) taken.add(hexKey(hex(f.q, f.r)));
  for (const c of await listCamps(client, worldId)) taken.add(hexKey(hex(c.q, c.r)));
  for (const s of await listSites(client, worldId)) taken.add(hexKey(hex(s.q, s.r)));
  return taken;
}

// The rampage is over: survivors make camp near where they stand.
async function settle(client: DbClient, data: GameData, world: World, wave: Wave, from: Hex, at: Date): Promise<void> {
  const units = wave.composition;
  const site = total(units) > 0 ? campSite(data, await terrainOf(client, world.id), from, await takenHexes(client, world.id)) : null;
  if (!site) {
    await finishWave(client, data, world, wave.id, 'dispersed', at);
  } else {
    await createCamp(
      client,
      data,
      world,
      { kind: wave.front === 'north' ? 'lair' : 'bandit', front: wave.front, q: site.q, r: site.r, units, waveId: wave.id },
      at,
    );
    await markSettled(client, wave.id, at);
    await afterSettling(client, data, world, wave.id, at);
    for (const member of await listMembers(client, world.id)) {
      await tell(client, world, member.accountId, {
        kind: 'camp',
        tier: 'digest',
        title: wave.front === 'north' ? `Monsters made a lair at (${site.q}, ${site.r})` : `Raiders made camp at (${site.q}, ${site.r})`,
        body: `${total(units)} survivors of wave ${wave.index + 1} settled there.`,
      }, at);
    }
    await notifyWorld(client, { worldId: world.id, type: 'world' });
  }
  await notifyWorld(client, { worldId: world.id, type: 'waves' });
}

// After a raid or raze at `from`: on to the next village it hasn't struck
// (or the Holy City), if the rampage clock allows; otherwise settle.
export async function moveOn(client: DbClient, data: GameData, world: World, waveId: number, from: Hex, at: Date): Promise<void> {
  const wave = await loadWave(client, waveId);
  const endsAt = wave.rampageEndsAt;
  if (!endsAt || at >= endsAt || total(wave.composition) === 0) return settle(client, data, world, wave, from, at);
  const villages = (await listVillages(client, world.id)).filter((v) => !v.ruin && !wave.struck.includes(v.id));
  const sinceSpawn = at.getTime() - wave.spawnAt.getTime();
  const route = routeFrom(data, {
    terrain: await terrainOf(client, world.id),
    from,
    targets: targetsOf(villages).filter((t) => t.cell.q !== from.q || t.cell.r !== from.r),
    front: wave.front,
    composition: wave.composition,
    fear: await fearOf(client, data, world),
    rng: rngFor(world.seed, wave.index, 0x90 + wave.struck.length),
    startMs: sinceSpawn,
    worldSpeed: world.speed,
  });
  if (!route) return settle(client, data, world, wave, from, at);
  const march = holdForQuiet(world, wave.spawnAt, { path: route.path, arrivesAt: new Date(wave.spawnAt.getTime() + route.arrivesMs) });
  const arrivesAt = march.arrivesAt;
  if (arrivesAt > endsAt) return settle(client, data, world, wave, from, at);
  await marchOnward(client, wave.id, route.targetVillageId, march.path, arrivesAt);
  await cancelPlans(client, world.id, wave.id);
  await scheduleEvent(client, world.id, arrivesAt, 'wave_arrive', { waveId: wave.id });
  await planRaids(client, data, world, wave.id, sinceSpawn + 1);
  await planIntercepts(client, world, wave.id, sinceSpawn + 1);
  await planWaveWarning(client, data, world, wave.id, at);
  await notifyWorld(client, { worldId: world.id, type: 'waves' });
}

// Everything burned: fields and buildings at 0, stores and troops gone.
function ruinedState(data: GameData, state: VillageState, at: Date, worldSpeed: number): VillageState {
  const plots = ruinPlots(state.plots);
  const levels = levelsOf(plots);
  const next: VillageState = {
    ...state,
    plots,
    levels,
    queue: [],
    training: [],
    garrison: {},
    besieged: false,
    ledger: { ...state.ledger, amounts: { wood: 0, stone: 0, grain: 0, iron: 0 }, settledAt: at },
  };
  return { ...next, ledger: withRates(next.ledger, at, villageRates(data, next, worldSpeed), capacity(data, levels, state.bonuses)) };
}

async function ruinVillage(client: DbClient, data: GameData, world: World, village: Village, at: Date): Promise<void> {
  if (village.ruin) return;
  await saveVillageState(client, village.id, ruinedState(data, village.state, at, world.speed));
  await saveRuin(client, village.id, { plots: { ...village.state.plots }, since: at.toISOString(), rebuildingUntil: null });
  await tell(client, world, village.ownerAccountId, {
    kind: 'razed',
    tier: 'push',
    title: `${village.name} was razed`,
    body: 'Only ruins are left. Rebuild them, or start over from what remains.',
  }, at);
  // Nothing left standing: a refugee camp by the Holy City.
  const owner = village.ownerAccountId;
  if (owner !== null) {
    const standing = (await listVillages(client, world.id)).filter((v) => v.ownerAccountId === owner && !v.ruin && v.id !== village.id);
    const site = standing.length === 0 ? refugeeSite(data, await terrainOf(client, world.id), await takenHexes(client, world.id)) : null;
    if (site) {
      const member = (await listMembers(client, world.id)).find((m) => m.accountId === owner);
      const camp = await insertVillage(client, {
        worldId: world.id,
        ownerAccountId: owner,
        name: data.horde.refugeeCamp.name.replace('{owner}', member?.displayName ?? 'Refugees'),
        q: site.q,
        r: site.r,
        state: newVillage(data, at, world.speed, {
          startingResources: data.buildings.village.startingResources,
          adminUpkeep: 0,
          bonuses: await playerBonuses(client, data, world.id, owner),
        }),
      });
      await markRefuge(client, camp.id);
      await tell(client, world, owner, {
        kind: 'refuge',
        tier: 'push',
        title: `A refuge by the Holy City`,
        body: `${camp.name} takes in your people at (${site.q}, ${site.r}).`,
      }, at);
    }
  }
  await notifyWorld(client, { worldId: world.id, type: 'world' });
}

// Paid for and started by rebuildCommand: the village stands again.
export async function startRebuild(client: DbClient, data: GameData, world: World, village: Village, at: Date): Promise<Date> {
  const until = new Date(at.getTime() + rebuildMs(data, world.speed));
  await saveRuin(client, village.id, { ...village.ruin!, rebuildingUntil: until.toISOString() });
  const payload: RebuildPayload = { villageId: village.id };
  await scheduleEvent(client, world.id, until, 'village_rebuilt', payload);
  return until;
}

// A horde at the Holy City fights its guard and anyone holding the city.
export async function startHolyCityBattle(client: DbClient, data: GameData, world: World, wave: Wave, at: Date): Promise<Battle> {
  const guard = holyCityGuard(data, wave.index);
  await markBattling(client, wave.id);
  const holders = (await listArmies(client, world.id)).filter(
    (a) => a.targetVillageId === null && a.targetQ === 0 && a.targetR === 0 && a.status === 'stationed',
  );
  const defenders: Record<string, number> = { ...guard };
  for (const army of holders) for (const [unit, n] of Object.entries(army.units)) defenders[unit] = (defenders[unit] ?? 0) + n;
  const battle = await insertBattle(client, {
    worldId: world.id,
    waveId: wave.id,
    villageId: null,
    q: 0,
    r: 0,
    setup: { holyCity: true, guard },
    attackerStance: wave.stance,
    attackerInitial: wave.composition,
    defenderInitial: defenders,
    startedAt: at,
  });
  for (const army of holders) await saveArmy(client, { ...army, status: 'engaged', battleId: battle.id, joinsRound: 1, joinBonus: 0 });
  await scheduleEvent(client, world.id, new Date(at.getTime() + roundMs(data, world.speed)), 'battle_round', { battleId: battle.id });
  for (const member of await listMembers(client, world.id)) {
    await tell(client, world, member.accountId, {
      kind: 'under_attack',
      tier: 'push',
      title: 'A horde is at the Holy City',
      body: `${total(wave.composition)} of them against its guard of ${total(defenders)}.`,
    }, at);
  }
  await notifyWorld(client, { worldId: world.id, type: 'battles' });
  await notifyWorld(client, { worldId: world.id, type: 'armies' });
  return battle;
}

export const hordeHandlers: HandlerRegistry = {
  async wave_raze({ client, data, world }, event) {
    const payload = razePayload.parse(event.payload);
    const wave = await loadWave(client, payload.waveId);
    if (wave.status !== 'razing') return;
    const village = await loadVillage(client, payload.villageId);
    await ruinVillage(client, data, world, village, event.dueAt);
    await moveOn(client, data, world, wave.id, hex(village.q, village.r), event.dueAt);
  },

  async village_rebuilt({ client, data, world }, event) {
    const village = await loadVillage(client, rebuildPayload.parse(event.payload).villageId);
    const ruin = village.ruin;
    if (!ruin?.rebuildingUntil || new Date(ruin.rebuildingUntil) > event.dueAt) return;
    const plots = { ...village.state.plots, ...ruin.plots };
    const levels = levelsOf(plots);
    const next = { ...village.state, plots, levels };
    const state: VillageState = {
      ...next,
      ledger: withRates(village.state.ledger, event.dueAt, villageRates(data, next, world.speed), capacity(data, levels, next.bonuses)),
    };
    await saveVillageState(client, village.id, state);
    await saveRuin(client, village.id, null);
    await tell(client, world, village.ownerAccountId, {
      kind: 'build_done',
      tier: 'push',
      title: `${village.name} stands again`,
      body: 'Its fields and buildings are rebuilt as they were.',
    }, event.dueAt);
    await notifyWorld(client, { worldId: world.id, type: 'world' });
  },
};
