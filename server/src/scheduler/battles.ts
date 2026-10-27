// Battles on the scheduler: a horde reaching a village starts a battle; each
// battle_round event fights one round, applies losses to the horde and the
// garrison, and either schedules the next round or settles the outcome.
import { createRng } from '../sim/rng.js';
import { againstFront, villageBonuses } from '../sim/clans.js';
import { z } from 'zod';
import type { GameData } from '../data/index.js';
import { insertBattle, loadBattle, recordRound, saveSetup, setDecision, type BattleSetup, type RoundLog } from '../db/battles.js';
import { notifyWorld } from '../db/notify.js';
import { riverKeys } from '../db/rivers.js';
import { cameOverRiver } from '../sim/field.js';
import type { DbClient } from '../db/pool.js';
import { loadVillage, saveVillageState } from '../db/villages.js';
import { loadWave, markBattling, setWaveStrength, type Wave } from '../db/waves.js';
import { finishWave } from './camps.js';
import type { World } from '../db/worlds.js';
import {
  battleOutcome,
  battleRng,
  enemyStats,
  playerStats,
  raidLoot,
  resolveRound,
  roundMs,
  subtractUnits,
  total,
} from '../sim/battle.js';
import { amountsAt } from '../sim/resources.js';
import { breachWalls, completeTraining, joinGarrison, hospitalHealed, loseGarrison, plunder, setBesieged } from '../sim/village.js';
import { heroAt } from '../db/heroes.js';
import { generalAt } from '../db/generals.js';
import { generalBonuses } from '../sim/generals.js';
import { generalAfterBattle } from './generals.js';
import { combine, heroBonuses } from '../sim/heroes.js';
import { tell } from './notices.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';
import { heroAfterBattle } from './heroes.js';
import { hordeStats, leaderAfter } from './leaders.js';
import { armyLosses, planHunger, rallyToBattle, sendHome } from './armies.js';
import { armiesInBattle, saveArmy, type Army } from '../db/armies.js';
import { addUnits, splitLosses } from '../sim/armies.js';
import { fieldRound } from './field.js';
import { hordeBeaten, hordeWins, moveOn } from './horde.js';
import { hex } from '../sim/hex.js';
import { ballistaKills, heldBack, overTheWalls, siegeDamage, siegeWorks, towerLevel, wallFactors, wallIntegrity, wallLevel } from '../sim/walls.js';
import { record } from '../db/telemetry.js';

export function personality(data: GameData, wave: Wave) {
  return data.enemies.fronts[wave.front]!.personality;
}

export const battlePayload = z.object({ battleId: z.number().int() });
export type BattlePayload = z.infer<typeof battlePayload>;

export async function startBattle(
  client: DbClient,
  data: GameData,
  world: World,
  wave: Wave,
  villageId: number,
  at: Date,
): Promise<void> {
  const village = await loadVillage(client, villageId);
  // Units that finished training by now stand with the garrison; the
  // village's outposts stop producing while the battle lasts.
  const state = setBesieged(data, completeTraining(village.state, at), true, at, world.speed);
  await saveVillageState(client, village.id, state);
  await markBattling(client, wave.id);
  // Walls must be battered down; a horde without the siege to do it in time
  // builds engines first, and the assault waits for them.
  const setup: BattleSetup = {};
  if (cameOverRiver(wave.path ?? [], { q: village.q, r: village.r }, await riverKeys(client, world.id))) setup.river = true;
  let composition = wave.composition;
  let firstRound = at.getTime() + roundMs(data, world.speed);
  const integrity = wallIntegrity(data, state.plots);
  if (integrity > 0) {
    const moat = towerLevel(state.plots, 'ditch');
    setup.wall = { level: wallLevel(state.plots), integrity, max: integrity, ...(moat > 0 ? { moat } : {}) };
    const works = siegeWorks(data, wave.front, composition, integrity, state.plots, world.speed);
    if (works) {
      firstRound += works.setupMs;
      composition = addUnits(composition, { [works.engine]: works.count });
      setup.siege = { engine: works.engine, count: works.count, readyAt: new Date(at.getTime() + works.setupMs).toISOString() };
      await setWaveStrength(client, wave.id, composition);
    }
  }
  const battle = await insertBattle(client, {
    worldId: world.id,
    waveId: wave.id,
    villageId,
    q: village.q,
    r: village.r,
    setup,
    attackerStance: wave.stance,
    attackerInitial: composition,
    defenderInitial: state.garrison,
    startedAt: at,
  });
  const payload: BattlePayload = { battleId: battle.id };
  await scheduleEvent(client, world.id, new Date(firstRound), 'battle_round', payload);
  await rallyToBattle(client, data, world, battle, { ...village, state }, at);
  await notifyWorld(client, { worldId: world.id, type: 'village', villageId });
  await notifyWorld(client, { worldId: world.id, type: 'battles' });
  await tell(client, world, village.ownerAccountId, {
    kind: 'under_attack',
    tier: 'push',
    title: '{village} is under attack',
    body: 'A horde of {enemy} is fighting your garrison of {defenders}.',
    vars: { village: village.name, enemy: total(wave.composition), defenders: total(state.garrison) },
  }, at);
}

export const battleHandlers: HandlerRegistry = {
  async battle_round({ client, data, world }, event) {
    const battle = await loadBattle(client, battlePayload.parse(event.payload).battleId);
    if (battle.status !== 'ongoing') return;
    if (battle.waveId === null) return;
    if (battle.villageId === null) {
      await fieldRound(client, data, world, battle, event.dueAt);
      return;
    }
    const wave = await loadWave(client, battle.waveId);
    const village = await loadVillage(client, battle.villageId);
    const at = event.dueAt;
    const state = completeTraining(village.state, at);

    const round = battle.round + 1;
    // The hero standing in the village leads its garrison, with the general
    // commanding it.
    const hero = await heroAt(client, village.id);
    const general = await generalAt(client, village.id);
    // The horde's leader drives it on, hardest against a village they hate.
    const led = await hordeStats(client, data, wave, enemyStats(data, wave.front), village.id);
    const own = againstFront(villageBonuses(data, state), wave.front);
    const heroic = hero ? combine(own, heroBonuses(data, hero)) : own;
    const bonuses = general ? combine(heroic, generalBonuses(data, general)) : heroic;
    // The garrison fights alongside armies sent to help; armies joining this
    // round bring their pincer or harassment bonus.
    const engaged = await armiesInBattle(client, battle.id);
    const forces = [state.garrison, ...engaged.map((a) => a.units)];
    const joining = engaged.filter((a) => a.joinsRound === round);
    const surge = 1 + joining.reduce((sum, a) => sum + a.joinBonus, 0);
    const baseStats = playerStats(data, bonuses, true);
    // While the walls stand they toughen the garrison, its archers shoot
    // from them and its towers with them; ballistae smash engines before
    // the horde closes, and its fighters can't come to grips but where
    // climbers carry them over.
    const rng = battleRng(world.seed, battle.id, round);
    const wall = battle.setup.wall;
    const standing = !!wall && wall.integrity > 0;
    const smashed = standing ? ballistaKills(data, wave.front, wave.composition, state.plots, rng) : {};
    const assault = subtractUnits(wave.composition, smashed);
    const defenders = forces.reduce<Record<string, number>>((sum, f) => addUnits(sum, f), {});
    const archers = Object.entries(defenders).reduce((sum, [unit, n]) => sum + (data.units.units[unit]?.family === 'archers' ? n : 0), 0);
    const over = standing ? overTheWalls(data, wave.front, assault, state.plots) : 0;
    const walls = standing ? wallFactors(data, state.plots, archers, over) : { defense: 1, attack: 1, archers: 1 };
    const held = standing ? heldBack(data, over) : 1;
    // A horde that came over a river into the fight strikes weaker.
    const river = battle.setup.river ? data.field.river.attackerFactor : 1;
    const result = resolveRound(
      data,
      {
        units: assault,
        stance: battle.attackerStance,
        stats: (unit) => {
          const base = led.stats(unit);
          return { ...base, attack: base.attack * river * (base.family === 'archers' ? 1 : held) };
        },
        home: false,
      },
      {
        units: defenders,
        stance: state.stance,
        stats: (unit) => {
          const base = baseStats(unit);
          const shooting = base.family === 'archers' ? walls.archers : 1;
          return { ...base, attack: base.attack * surge * walls.attack * shooting, defense: base.defense * walls.defense };
        },
        home: true,
      },
      rng,
    );
    const attackerLosses = addUnits(result.attackerLosses, smashed);
    const attackerNow = subtractUnits(wave.composition, attackerLosses);
    // The horde batters the walls with what came at them this round.
    let wallLeft: number | undefined;
    if (standing) {
      wallLeft = Math.max(0, Math.round(wall.integrity - siegeDamage(data, wave.front, assault, state.plots)));
      await saveSetup(client, battle.id, { ...battle.setup, wall: { ...wall, integrity: wallLeft } });
    }
    const shares = splitLosses(result.defenderLosses, forces);
    let villageState = loseGarrison(data, state, shares[0]!, at, world.speed);
    let defenderLosses: Record<string, number> = { ...shares[0]! };
    const armies: Army[] = [];
    for (const [i, army] of engaged.entries()) {
      let losses = shares[i + 1]!;
      // Harassers strike and ride off before the horde can close.
      if (army.orders === 'harass' && army.joinsRound === round) {
        losses = Object.fromEntries(Object.entries(losses).map(([u, n]) => [u, Math.floor(n * data.armies.harass.lossFactor)]));
      }
      defenderLosses = addUnits(defenderLosses, losses);
      armies.push(await armyLosses(client, data, world, army, losses, at));
    }
    const leaving = (a: Army) => a.orders === 'harass' && a.joinsRound === round;
    const defendersNow = armies
      .filter((a) => !leaving(a))
      .reduce<Record<string, number>>((sum, a) => addUnits(sum, a.units), { ...villageState.garrison });
    await setWaveStrength(client, wave.id, attackerNow);

    const outcome = battleOutcome(data, {
      round,
      attackerStance: battle.attackerStance,
      attackerInitial: battle.attackerInitial,
      attackerNow,
      defenderStance: state.stance,
      defenderInitial: battle.defenderInitial,
      defenderNow: defendersNow,
      attackerNerve: personality(data, wave).nerve * (1 + led.nerve),
    });
    const log: RoundLog = {
      round,
      at: at.toISOString(),
      attackerLosses,
      defenderLosses,
      attackerLeft: total(attackerNow),
      defenderLeft: total(defendersNow),
      ...(joining.length
        ? {
            joined: joining.map((a) => ({ armyId: a.id, villageId: a.homeVillageId, orders: a.orders, units: a.units, bonus: a.joinBonus })),
          }
        : {}),
      ...(wallLeft !== undefined ? { wallLeft, breach: wallLeft === 0 } : {}),
      ...(total(smashed) ? { smashed } : {}),
      ...(over > 0 ? { over: Math.round(over * 100) / 100 } : {}),
      ...(engaged.length ? { garrisonLosses: shares[0]! } : {}),
    };
    // Armies after the round: harassers ride home; when the battle is over,
    // support stays on guard and reinforcements go home.
    for (const army of armies) {
      if (leaving(army) || (outcome !== 'ongoing' && army.orders !== 'support')) await sendHome(client, world, army, at, data);
      else if (outcome !== 'ongoing') {
        if (total(army.units)) await planHunger(client, data, world, { ...army, status: 'stationed', battleId: null, joinsRound: null, joinBonus: 0 }, at);
        else await saveArmy(client, { ...army, status: 'done' });
      } else await saveArmy(client, total(army.units) ? army : { ...army, status: 'done' });
    }
    if (engaged.length) await notifyWorld(client, { worldId: world.id, type: 'armies' });

    let razed = false;
    if (outcome === 'ongoing') {
      await recordRound(client, battle.id, log, null);
      const payload: BattlePayload = { battleId: battle.id };
      await scheduleEvent(client, world.id, new Date(at.getTime() + roundMs(data, world.speed)), 'battle_round', payload);
    } else if (outcome === 'raided') {
      // The horde decides: carry off what it can and move on, or stay and
      // burn the village to the ground (horde.ts).
      const decision = await hordeWins(client, data, world, wave, village, attackerNow, at);
      razed = decision.choice === 'raze';
      await setDecision(client, battle.id, decision);
      if (decision.choice === 'raid') {
        const loot = raidLoot(data, amountsAt(villageState.ledger, at), battle.attackerInitial, attackerNow, bonuses, personality(data, wave).lootFactor * (1 + led.loot));
        // A raid, like a raze, burns whatever was being built.
        const lostBuilds = villageState.queue.length;
        villageState = { ...plunder(villageState, loot, at), queue: [] };
        villageState = setBesieged(data, villageState, false, at, world.speed);
        await recordRound(client, battle.id, log, { status: 'raided', at, loot });
        await tell(client, world, village.ownerAccountId, {
          kind: 'battle_result',
          tier: 'digest',
          title: '{village} was raided',
          body: lostBuilds
            ? `The horde carried off {loot} resources after {rounds} rounds. The work on {buildings} building${lostBuilds === 1 ? '' : 's'} was lost.`
            : 'The horde carried off {loot} resources after {rounds} rounds.',
          vars: { village: village.name, loot: total(loot), rounds: round, buildings: lostBuilds },
        }, at);
      } else {
        await recordRound(client, battle.id, log, { status: 'raided', at, loot: null });
        await tell(client, world, village.ownerAccountId, {
          kind: 'razing',
          tier: 'push',
          title: '{village} is being razed',
          body: 'The horde broke the defenders after {rounds} rounds and is burning the village.',
          vars: { village: village.name, rounds: round },
        }, at);
      }
    } else {
      villageState = setBesieged(data, villageState, false, at, world.speed);
      // The hospital puts some of the garrison's fallen back on their feet.
      const fallen = [...battle.rounds, log].reduce<Record<string, number>>((sum, r) => addUnits(sum, r.garrisonLosses ?? r.defenderLosses), {});
      const healed = hospitalHealed(villageBonuses(data, villageState), fallen, createRng((world.seed ^ Math.imul(battle.id + 1, 0x2545f491) ^ 0x4b) >>> 0));
      if (total(healed) > 0) {
        log.healed = healed;
        villageState = joinGarrison(data, villageState, healed, at, world.speed);
      }
      await recordRound(client, battle.id, log, { status: 'defended', at, loot: null });
      await hordeBeaten(client, data, world, hex(village.q, village.r), total(battle.attackerInitial) - total(attackerNow));
      await tell(client, world, village.ownerAccountId, {
        kind: 'battle_result',
        tier: 'digest',
        title: '{village} held',
        body: total(healed) > 0 ? 'The horde was beaten after {rounds} rounds; the hospital saved {healed} of the fallen.' : 'The horde was beaten after {rounds} rounds.',
        vars: { village: village.name, rounds: round, healed: total(healed) },
      }, at);
      await finishWave(client, data, world, wave.id, 'defeated', at);
    }

    // A breach knocks the walls down a level.
    if (outcome !== 'ongoing' && wall && (wallLeft ?? wall.integrity) === 0) villageState = breachWalls(data, villageState);
    await saveVillageState(client, village.id, villageState);
    if (outcome !== 'ongoing') {
      await record(client, world.id, 'wave_result', {
        wave: wave.index,
        front: wave.front,
        threat: wave.threat,
        where: 'village',
        outcome: outcome === 'defended' ? 'held' : razed ? 'razed' : 'raided',
        rounds: round,
        horde: total(battle.attackerInitial),
        defenders: total(battle.defenderInitial),
        walls: battle.setup.wall?.level ?? 0,
      }, at);
      const kills = total(defenderLosses) + battle.rounds.reduce((n, r) => n + total(r.defenderLosses), 0);
      await leaderAfter(client, data, world, wave, { hordeWon: outcome === 'raided', razed, kills, wiped: total(attackerNow) === 0, villageId: village.id }, at);
    }
    // A raiding horde moves on once the village is saved.
    if (outcome === 'raided' && (await loadWave(client, wave.id)).status === 'battling') {
      await moveOn(client, data, world, wave.id, hex(village.q, village.r), at);
    }
    if (hero && outcome !== 'ongoing') {
      const kills = total(battle.attackerInitial) - total(attackerNow);
      await heroAfterBattle(client, data, world, hero, { kills, won: outcome !== 'raided', battleId: battle.id, at });
    }
    if (general && outcome !== 'ongoing') {
      const kills = total(battle.attackerInitial) - total(attackerNow);
      await generalAfterBattle(client, data, world, general, { kills, won: outcome !== 'raided', at });
    }
    await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
    await notifyWorld(client, { worldId: world.id, type: 'battles' });
    if (outcome !== 'ongoing') await notifyWorld(client, { worldId: world.id, type: 'waves' });
  },
};
