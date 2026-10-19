// Battles on the scheduler: a horde reaching a village starts a battle; each
// battle_round event fights one round, applies losses to the horde and the
// garrison, and either schedules the next round or settles the outcome.
import { z } from 'zod';
import type { GameData } from '../data/index.js';
import { insertBattle, loadBattle, recordRound, setDecision, type RoundLog } from '../db/battles.js';
import { notifyWorld } from '../db/notify.js';
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
import { completeTraining, loseGarrison, plunder, setBesieged } from '../sim/village.js';
import { heroAt } from '../db/heroes.js';
import { combine, heroBonuses } from '../sim/heroes.js';
import { tell } from './notices.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';
import { heroAfterBattle } from './heroes.js';
import { armyLosses, rallyToBattle, sendHome } from './armies.js';
import { armiesInBattle, saveArmy, type Army } from '../db/armies.js';
import { addUnits, splitLosses } from '../sim/armies.js';
import { fieldRound } from './field.js';
import { hordeBeaten, hordeWins, moveOn } from './horde.js';
import { hex } from '../sim/hex.js';

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
  const battle = await insertBattle(client, {
    worldId: world.id,
    waveId: wave.id,
    villageId,
    q: village.q,
    r: village.r,
    attackerStance: wave.stance,
    attackerInitial: wave.composition,
    defenderInitial: state.garrison,
    startedAt: at,
  });
  const payload: BattlePayload = { battleId: battle.id };
  await scheduleEvent(client, world.id, new Date(at.getTime() + roundMs(data, world.speed)), 'battle_round', payload);
  await rallyToBattle(client, data, world, battle, { ...village, state }, at);
  await notifyWorld(client, { worldId: world.id, type: 'village', villageId });
  await notifyWorld(client, { worldId: world.id, type: 'battles' });
  await tell(client, world, village.ownerAccountId, {
    kind: 'under_attack',
    tier: 'push',
    title: `${village.name} is under attack`,
    body: `A horde of ${total(wave.composition)} is fighting your garrison of ${total(state.garrison)}.`,
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
    // The hero standing in the village leads its garrison.
    const hero = await heroAt(client, village.id);
    const bonuses = hero ? combine(state.bonuses, heroBonuses(data, hero)) : state.bonuses;
    // The garrison fights alongside armies sent to help; armies joining this
    // round bring their pincer or harassment bonus.
    const engaged = await armiesInBattle(client, battle.id);
    const forces = [state.garrison, ...engaged.map((a) => a.units)];
    const joining = engaged.filter((a) => a.joinsRound === round);
    const surge = 1 + joining.reduce((sum, a) => sum + a.joinBonus, 0);
    const baseStats = playerStats(data, bonuses, true);
    const result = resolveRound(
      data,
      { units: wave.composition, stance: battle.attackerStance, stats: enemyStats(data, wave.front), home: false },
      {
        units: forces.reduce<Record<string, number>>((sum, f) => addUnits(sum, f), {}),
        stance: state.stance,
        stats: surge === 1 ? baseStats : (unit) => ({ ...baseStats(unit), attack: baseStats(unit).attack * surge }),
        home: true,
      },
      battleRng(world.seed, battle.id, round),
    );
    const attackerNow = subtractUnits(wave.composition, result.attackerLosses);
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
      attackerNerve: personality(data, wave).nerve,
    });
    const log: RoundLog = {
      round,
      at: at.toISOString(),
      attackerLosses: result.attackerLosses,
      defenderLosses,
      attackerLeft: total(attackerNow),
      defenderLeft: total(defendersNow),
      ...(joining.length
        ? {
            joined: joining.map((a) => ({ armyId: a.id, villageId: a.homeVillageId, orders: a.orders, units: a.units, bonus: a.joinBonus })),
          }
        : {}),
    };
    // Armies after the round: harassers ride home; when the battle is over,
    // support stays on guard and reinforcements go home.
    for (const army of armies) {
      if (leaving(army) || (outcome !== 'ongoing' && army.orders !== 'support')) await sendHome(client, world, army, at, data);
      else if (outcome !== 'ongoing') {
        await saveArmy(client, total(army.units) ? { ...army, status: 'stationed', battleId: null, joinsRound: null, joinBonus: 0 } : { ...army, status: 'done' });
      } else await saveArmy(client, total(army.units) ? army : { ...army, status: 'done' });
    }
    if (engaged.length) await notifyWorld(client, { worldId: world.id, type: 'armies' });

    if (outcome === 'ongoing') {
      await recordRound(client, battle.id, log, null);
      const payload: BattlePayload = { battleId: battle.id };
      await scheduleEvent(client, world.id, new Date(at.getTime() + roundMs(data, world.speed)), 'battle_round', payload);
    } else if (outcome === 'raided') {
      // The horde decides: carry off what it can and move on, or stay and
      // burn the village to the ground (horde.ts).
      const decision = await hordeWins(client, data, world, wave, village, attackerNow, at);
      await setDecision(client, battle.id, decision);
      if (decision.choice === 'raid') {
        const loot = raidLoot(data, amountsAt(villageState.ledger, at), battle.attackerInitial, attackerNow, bonuses, personality(data, wave).lootFactor);
        villageState = plunder(villageState, loot, at);
        villageState = setBesieged(data, villageState, false, at, world.speed);
        await recordRound(client, battle.id, log, { status: 'raided', at, loot });
        await tell(client, world, village.ownerAccountId, {
          kind: 'battle_result',
          tier: 'digest',
          title: `${village.name} was raided`,
          body: `The horde carried off ${total(loot)} resources after ${round} rounds.`,
        }, at);
      } else {
        await recordRound(client, battle.id, log, { status: 'raided', at, loot: null });
        await tell(client, world, village.ownerAccountId, {
          kind: 'razing',
          tier: 'push',
          title: `${village.name} is being razed`,
          body: `The horde broke the defenders after ${round} rounds and is burning the village.`,
        }, at);
      }
    } else {
      villageState = setBesieged(data, villageState, false, at, world.speed);
      await recordRound(client, battle.id, log, { status: 'defended', at, loot: null });
      await hordeBeaten(client, data, world, hex(village.q, village.r), total(battle.attackerInitial) - total(attackerNow));
      await tell(client, world, village.ownerAccountId, {
        kind: 'battle_result',
        tier: 'digest',
        title: `${village.name} held`,
        body: `The horde was beaten after ${round} rounds.`,
      }, at);
      await finishWave(client, data, world, wave.id, 'defeated', at);
    }

    await saveVillageState(client, village.id, villageState);
    // A raiding horde moves on once the village is saved.
    if (outcome === 'raided' && (await loadWave(client, wave.id)).status === 'battling') {
      await moveOn(client, data, world, wave.id, hex(village.q, village.r), at);
    }
    if (hero && outcome !== 'ongoing') {
      const kills = total(battle.attackerInitial) - total(attackerNow);
      await heroAfterBattle(client, data, world, hero, { kills, won: outcome !== 'raided', battleId: battle.id, at });
    }
    await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
    await notifyWorld(client, { worldId: world.id, type: 'battles' });
    if (outcome !== 'ongoing') await notifyWorld(client, { worldId: world.id, type: 'waves' });
  },
};
