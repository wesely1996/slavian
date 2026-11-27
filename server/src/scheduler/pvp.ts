// Player against player (armies.json pvp, sim/pvp.ts): an army sent to
// attack another player's village arrives and fights at once. Won, it
// plunders the stores or razes the village; then it comes home.
import { seasonAt, seasonDefense } from '../sim/seasons.js';
import type { GameData } from '../data/index.js';
import { armiesAt, type Army } from '../db/armies.js';
import { insertBattle, recordRound, type RoundLog } from '../db/battles.js';
import { generalAt, generalWithArmy } from '../db/generals.js';
import { heroAt, heroWithArmy } from '../db/heroes.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { loadVillage, saveVillageState } from '../db/villages.js';
import { listMembers, type World } from '../db/worlds.js';
import { addUnits } from '../sim/armies.js';
import { playerStats, total, type UnitStats } from '../sim/battle.js';
import { villageBonuses } from '../sim/clans.js';
import { protectedUntil, pvpAssault, pvpLoot, type PvpForce } from '../sim/pvp.js';
import { amountsAt, mapResources } from '../sim/resources.js';
import { combatants, withIntel } from '../sim/scouting.js';
import { completeTraining, loseGarrison, plunder } from '../sim/village.js';
import { wallFactors, wallIntegrity } from '../sim/walls.js';
import { armyLosses, sendHome } from './armies.js';
import { championsFall, championsOf, commandBonuses } from './champions.js';
import { ruinVillage } from './horde.js';
import { groundOf, roadAt } from './ground.js';
import { tell } from './notices.js';
import { commandOf } from '../sim/lines.js';

export async function attackVillage(client: DbClient, data: GameData, world: World, army: Army, at: Date): Promise<void> {
  const target = army.targetVillageId !== null ? await loadVillage(client, army.targetVillageId).catch(() => null) : null;
  const attacker = (await listMembers(client, world.id)).find((m) => m.accountId === army.ownerAccountId)?.displayName ?? '?';
  // Nothing to attack any more (or not now): it comes home.
  const until = target ? protectedUntil(data, world, target.foundedAt) : null;
  if (!world.pvp || !target || target.ruin || target.ownerAccountId === null || target.ownerAccountId === army.ownerAccountId || (until && at < until)) {
    await sendHome(client, world, army, at, data);
    return;
  }
  const state = completeTraining(target.state, at);
  // The attackers: the army, led by its hero (else its general).
  const home = await loadVillage(client, army.homeVillageId);
  const hero = await heroWithArmy(client, army.id);
  const general = await generalWithArmy(client, army.id);
  const owned = villageBonuses(data, home.state);
  const attackers = combatants(data, army.units);
  const attackerForce: PvpForce = {
    units: attackers,
    stance: army.stance,
    stats: withIntel(data, army.units, playerStats(data, commandBonuses(data, owned, hero, general), false)),
    champions: championsOf(data, hero, general, owned),
  };
  // The defenders, behind the walls while they stand; each battering ram
  // takes its share of them off.
  const breach = Object.entries(attackers).reduce((n, [unit, count]) => n + (data.units.units[unit]?.breach ?? 0) * count, 0);
  const standing = wallIntegrity(data, state.plots) > 0 ? Math.max(0, 1 - breach) : 0;
  const stationed = await armiesAt(client, target.id, ['stationed']);
  const defenders = stationed.reduce((sum, a) => addUnits(sum, combatants(data, a.units)), combatants(data, state.garrison));
  const archers = Object.entries(defenders).reduce((n, [unit, count]) => n + (data.units.units[unit]?.family === 'archers' ? count : 0), 0);
  const full = wallFactors(data, state.plots, archers, 0);
  const walls = { defense: 1 + (full.defense - 1) * standing, attack: 1 + (full.attack - 1) * standing, archers: 1 + (full.archers - 1) * standing };
  const behindWalls = (stats: (unit: string) => UnitStats) => (unit: string): UnitStats => {
    const base = stats(unit);
    return { ...base, attack: base.attack * walls.attack * (base.family === 'archers' ? walls.archers : 1), defense: base.defense * walls.defense };
  };
  const villageHero = await heroAt(client, target.id);
  const villageGeneral = await generalAt(client, target.id);
  const own = villageBonuses(data, state);
  const forces: PvpForce[] = [
    {
      units: combatants(data, state.garrison),
      stance: state.stance,
      stats: behindWalls(playerStats(data, commandBonuses(data, own, villageHero, villageGeneral), true)),
      champions: championsOf(data, villageHero, villageGeneral, own),
    },
  ];
  const leaders = [];
  for (const a of stationed) {
    const theirs = villageBonuses(data, (await loadVillage(client, a.homeVillageId)).state);
    const aHero = await heroWithArmy(client, a.id);
    const aGeneral = await generalWithArmy(client, a.id);
    leaders.push({ hero: aHero, general: aGeneral });
    forces.push({
      units: combatants(data, a.units),
      stance: a.stance,
      stats: behindWalls(withIntel(data, a.units, playerStats(data, commandBonuses(data, theirs, aHero, aGeneral), true))),
      champions: championsOf(data, aHero, aGeneral, theirs),
    });
  }
  const result = pvpAssault(data, {
    attacker: attackerForce,
    statsWithoutHero: withIntel(data, army.units, playerStats(data, commandBonuses(data, owned, null, general), false)),
    defenders: forces,
    seed: world.seed,
    season: seasonDefense(data, seasonAt(data, world, at).season),
    id: army.id,
    ground: await groundOf(client, data, world.id, { q: target.q, r: target.r }),
    // In lines; nobody maneuvers at standing walls.
    lines: {
      attacker: commandOf(data, army.maneuver, [{ hero, general }]),
      defender: commandOf(data, 
        target.state.maneuver ?? 'encircle',
        [{ hero: villageHero, general: villageGeneral }, ...leaders],
        await roadAt(client, world.id, { q: target.q, r: target.r }),
      ),
      still: standing > 0,
    },
  });
  const battle = await insertBattle(client, {
    worldId: world.id,
    waveId: null,
    villageId: target.id,
    q: target.q,
    r: target.r,
    setup: { pvp: { attackerAccountId: army.ownerAccountId, armyId: army.id, raze: army.orders === 'raze' } },
    attackerStance: army.stance,
    attackerInitial: attackers,
    defenderInitial: defenders,
    startedAt: at,
  });
  // Losses: the attackers, the garrison, each army standing there.
  const lost = (before: Record<string, number>, after: Record<string, number>) =>
    Object.fromEntries(Object.entries(before).filter(([unit, n]) => n - (after[unit] ?? 0) > 0).map(([unit, n]) => [unit, n - (after[unit] ?? 0)]));
  const kills = total(defenders) - result.defendersNow.reduce((n, d) => n + total(d), 0);
  const fell = { kills, battleId: battle.id, at };
  await championsFall(client, data, world, result.attackerFallen, { hero, general, homeVillageId: army.homeVillageId }, fell);
  await championsFall(client, data, world, result.defenderFallen[0] ?? [], { hero: villageHero, general: villageGeneral, homeVillageId: null }, fell);
  let after = await armyLosses(client, data, world, army, lost(attackers, result.attackerNow), at);
  let villageState = loseGarrison(data, state, lost(forces[0]!.units, result.defendersNow[0]!), at, world.speed);
  for (const [i, a] of stationed.entries()) {
    await championsFall(client, data, world, result.defenderFallen[i + 1] ?? [], { ...leaders[i]!, homeVillageId: a.homeVillageId }, fell);
    const beaten = await armyLosses(client, data, world, a, lost(forces[i + 1]!.units, result.defendersNow[i + 1]!), at);
    // Beaten, the armies standing there fall back home.
    if (result.won) await sendHome(client, world, beaten, at, data);
  }
  const raze = result.won && army.orders === 'raze' && !target.refuge;
  let loot: Record<string, number> | null = null;
  if (result.won && !raze) {
    const carry = Object.entries(after.units).reduce((n, [unit, count]) => n + (data.units.units[unit]?.carry ?? 0) * count, 0);
    const stores = amountsAt(villageState.ledger, at);
    loot = pvpLoot(data, stores, carry);
    villageState = plunder(villageState, mapResources((kind) => loot![kind] ?? 0), at);
    after = { ...after, loot: mapResources((kind) => (after.loot?.[kind] ?? 0) + (loot![kind] ?? 0)) };
  }
  await saveVillageState(client, target.id, villageState);
  for (const [i, round] of result.rounds.entries()) {
    const log: RoundLog = { ...round, at: at.toISOString() };
    const last = i === result.rounds.length - 1;
    await recordRound(client, battle.id, log, last ? { status: result.won ? 'raided' : 'defended', at, loot: loot ? mapResources((kind) => loot![kind] ?? 0) : null } : null);
  }
  if (raze) await ruinVillage(client, data, world, { ...target, state: villageState }, at);
  await sendHome(client, world, after, at, data);
  const taken = loot ? Object.values(loot).reduce((n, v) => n + v, 0) : 0;
  await tell(client, world, target.ownerAccountId, {
    kind: result.won ? 'razed' : 'battle_result',
    tier: 'push',
    title: !result.won ? '{village} held against {player}' : raze ? '{village} was razed by {player}' : '{village} was plundered by {player}',
    body: !result.won
      ? "{player}'s army of {attackers} was beaten off; {kills} of them fell."
      : raze
        ? "{player}'s army broke the defenders and burned the village."
        : "{player}'s army broke the defenders and carried off {loot} resources.",
    vars: { village: target.name, player: attacker, attackers: total(attackers), kills: total(attackers) - total(result.attackerNow), loot: taken },
  }, at);
  await tell(client, world, army.ownerAccountId, {
    kind: 'battle_result',
    tier: 'push',
    title: !result.won ? 'Your army was beaten at {village}' : raze ? 'Your army razed {village}' : 'Your army plundered {village}',
    body: !result.won ? '{kills} of the defenders fell; the rest held.' : raze ? 'The village lies in ruins.' : 'It carries home {loot} resources.',
    vars: { village: target.name, kills, loot: taken },
  }, at);
  await notifyWorld(client, { worldId: world.id, type: 'village', villageId: target.id });
  await notifyWorld(client, { worldId: world.id, type: 'battles' });
}
