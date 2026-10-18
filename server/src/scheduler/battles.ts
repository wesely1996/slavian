// Battles on the scheduler: a horde reaching a village starts a battle; each
// battle_round event fights one round, applies losses to the horde and the
// garrison, and either schedules the next round or settles the outcome.
import { z } from 'zod';
import type { GameData } from '../data/index.js';
import { insertBattle, loadBattle, recordRound, type RoundLog } from '../db/battles.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { loadVillage, saveVillageState } from '../db/villages.js';
import { endWave, loadWave, markBattling, setWaveStrength, type Wave } from '../db/waves.js';
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
import { scheduleEvent, type HandlerRegistry } from './events.js';
import { heroAfterBattle } from './heroes.js';

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
    attackerStance: wave.stance,
    attackerInitial: wave.composition,
    defenderInitial: state.garrison,
    startedAt: at,
  });
  const payload: BattlePayload = { battleId: battle.id };
  await scheduleEvent(client, world.id, new Date(at.getTime() + roundMs(data, world.speed)), 'battle_round', payload);
  await notifyWorld(client, { worldId: world.id, type: 'village', villageId });
  await notifyWorld(client, { worldId: world.id, type: 'battles' });
}

export const battleHandlers: HandlerRegistry = {
  async battle_round({ client, data, world }, event) {
    const battle = await loadBattle(client, battlePayload.parse(event.payload).battleId);
    if (battle.status !== 'ongoing') return;
    const wave = await loadWave(client, battle.waveId);
    const village = await loadVillage(client, battle.villageId);
    const at = event.dueAt;
    const state = completeTraining(village.state, at);

    const round = battle.round + 1;
    // The hero standing in the village leads its garrison.
    const hero = await heroAt(client, village.id);
    const bonuses = hero ? combine(state.bonuses, heroBonuses(data, hero)) : state.bonuses;
    const result = resolveRound(
      data,
      { units: wave.composition, stance: battle.attackerStance, stats: enemyStats(data, wave.front), home: false },
      { units: state.garrison, stance: state.stance, stats: playerStats(data, bonuses, true), home: true },
      battleRng(world.seed, battle.id, round),
    );
    const attackerNow = subtractUnits(wave.composition, result.attackerLosses);
    let villageState = loseGarrison(data, state, result.defenderLosses, at, world.speed);
    await setWaveStrength(client, wave.id, attackerNow);

    const outcome = battleOutcome(data, {
      round,
      attackerStance: battle.attackerStance,
      attackerInitial: battle.attackerInitial,
      attackerNow,
      defenderStance: state.stance,
      defenderInitial: battle.defenderInitial,
      defenderNow: villageState.garrison,
    });
    const log: RoundLog = {
      round,
      at: at.toISOString(),
      attackerLosses: result.attackerLosses,
      defenderLosses: result.defenderLosses,
      attackerLeft: total(attackerNow),
      defenderLeft: total(villageState.garrison),
    };

    if (outcome === 'ongoing') {
      await recordRound(client, battle.id, log, null);
      const payload: BattlePayload = { battleId: battle.id };
      await scheduleEvent(client, world.id, new Date(at.getTime() + roundMs(data, world.speed)), 'battle_round', payload);
    } else if (outcome === 'raided') {
      const loot = raidLoot(data, amountsAt(villageState.ledger, at), battle.attackerInitial, attackerNow, bonuses);
      villageState = plunder(villageState, loot, at);
      villageState = setBesieged(data, villageState, false, at, world.speed);
      await recordRound(client, battle.id, log, { status: 'raided', at, loot });
      await endWave(client, wave.id, 'dispersed', at);
    } else {
      villageState = setBesieged(data, villageState, false, at, world.speed);
      await recordRound(client, battle.id, log, { status: 'defended', at, loot: null });
      await endWave(client, wave.id, 'defeated', at);
    }

    await saveVillageState(client, village.id, villageState);
    if (hero && outcome !== 'ongoing') {
      const kills = total(battle.attackerInitial) - total(attackerNow);
      await heroAfterBattle(client, data, world, hero, { kills, won: outcome !== 'raided', battleId: battle.id, at });
    }
    await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
    await notifyWorld(client, { worldId: world.id, type: 'battles' });
    if (outcome !== 'ongoing') await notifyWorld(client, { worldId: world.id, type: 'waves' });
  },
};
