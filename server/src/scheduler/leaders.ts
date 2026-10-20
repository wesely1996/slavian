// Enemy leaders in play (sim/leaders.ts): who heads a horde as it sets
// out, what they add in battle, and what a battle does to them.
import type { GameData } from '../data/index.js';
import type { DbClient } from '../db/pool.js';
import { aliveLeader, insertLeader, leadingNow, listLeaders, loadLeader, saveLeader, setWaveLeader, type EnemyLeader } from '../db/leaders.js';
import type { Wave } from '../db/waves.js';
import { notifyWorld } from '../db/notify.js';
import { listMembers, type World } from '../db/worlds.js';
import type { UnitStats } from '../sim/battle.js';
import { leaderAfterBattle, leaderEffects, leaderTitle, ledStats, newLeader, riseLevel, type LeaderOutcome } from '../sim/leaders.js';
import { tell } from './notices.js';

// The front's leader takes the head of a horde setting out, unless wounded
// or already out with another; a front without one raises a new leader,
// stronger for every one of theirs that fell.
export async function assignLeader(client: DbClient, data: GameData, world: World, wave: Wave, at: Date): Promise<EnemyLeader | null> {
  if (!data.leaders.fronts[wave.front]) return null;
  let leader = await aliveLeader(client, world.id, wave.front);
  if (!leader) {
    const all = await listLeaders(client, world.id);
    const fallen = all.filter((l) => l.front === wave.front && l.status === 'dead').at(-1);
    const state = newLeader(data, wave.front, world.seed + wave.index, all.map((l) => l.name), fallen ? riseLevel(data, fallen.level) : 1);
    leader = await insertLeader(client, world.id, wave.front, state, at);
  }
  if (leader.woundedUntil && leader.woundedUntil > at) return null;
  if (await leadingNow(client, leader.id)) return null;
  await setWaveLeader(client, wave.id, leader.id);
  return leader;
}

// The horde's unit stats under its leader, striking `villageId`.
export async function hordeStats(
  client: DbClient,
  data: GameData,
  wave: Wave,
  base: (unit: string) => UnitStats,
  villageId: number | null,
): Promise<{ stats: (unit: string) => UnitStats; nerve: number; loot: number }> {
  if (wave.leaderId === null) return { stats: base, nerve: 0, loot: 0 };
  const leader = await loadLeader(client, wave.leaderId);
  const effects = leaderEffects(data, leader);
  const grudge = villageId !== null && leader.grudgeVillageId === villageId;
  return { stats: ledStats(data, base, effects, grudge), nerve: effects.nerve, loot: effects.loot };
}

// After a battle the horde fought: experience, wounds, a grudge, or death.
export async function leaderAfter(client: DbClient, data: GameData, world: World, wave: Wave, outcome: LeaderOutcome, at: Date): Promise<void> {
  if (wave.leaderId === null) return;
  const leader = await loadLeader(client, wave.leaderId);
  if (leader.status === 'dead') return;
  const after = leaderAfterBattle(data, wave.front, leader, outcome, world.speed);
  const next: EnemyLeader = {
    ...leader,
    ...after.state,
    battles: leader.battles + 1,
    wins: leader.wins + (outcome.hordeWon ? 1 : 0),
    losses: leader.losses + (outcome.hordeWon ? 0 : 1),
    razed: leader.razed + (outcome.razed ? 1 : 0),
    kills: leader.kills + outcome.kills,
    status: after.dead ? 'dead' : 'alive',
    diedAt: after.dead ? at : null,
    woundedUntil: after.woundMs ? new Date(at.getTime() + after.woundMs) : leader.woundedUntil,
    grudgeVillageId: after.grudgeVillageId === undefined ? leader.grudgeVillageId : after.grudgeVillageId,
  };
  await saveLeader(client, next);
  const title = leaderTitle(data, wave.front, next);
  if (after.dead) {
    for (const member of await listMembers(client, world.id)) {
      await tell(client, world, member.accountId, {
        kind: 'leader',
        tier: 'digest',
        title: '{leader} has fallen',
        body: '{leader} died with the last of the horde after {battles} battles. Another will rise to take their place.',
        vars: { leader: title, battles: next.battles },
      }, at);
    }
  } else if (next.level > leader.level) {
    for (const member of await listMembers(client, world.id)) {
      await tell(client, world, member.accountId, {
        kind: 'leader',
        tier: 'digest',
        title: '{leader} grows stronger',
        body: '{leader} is now level {level}.',
        vars: { leader: leaderTitle(data, wave.front, leader), level: next.level },
      }, at);
    }
  }
  await notifyWorld(client, { worldId: world.id, type: 'waves' });
}
