// The enemy's forces on the scheduler (sim/enemyForces.ts): every watch
// (enemy_watch) the scouts of its settlements and war bands look for the
// players' armies in their front's lands; one they spot draws a sally from
// the nearest settlement and the front's patrols near it, who march on it
// (band_arrive), fight it where they catch it, chase it a little and go
// home. Patrols set out between settlements (enemy_patrol).
import { z } from 'zod';
import type { GameData } from '../data/index.js';
import { loadArmy, listArmies, saveArmy, type Army } from '../db/armies.js';
import { insertBattle, recordRound, type RoundLog } from '../db/battles.js';
import { deleteEnemyBand, insertEnemyBand, listEnemyBands, loadEnemyBand, saveEnemyBand, type EnemyBand } from '../db/enemyBands.js';
import { listEnemySettlements, setSallyReady, type EnemySettlement } from '../db/enemySettlements.js';
import { generalWithArmy } from '../db/generals.js';
import { heroWithArmy } from '../db/heroes.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { loadVillage } from '../db/villages.js';
import { listMembers, type World } from '../db/worlds.js';
import { playerStats, total } from '../sim/battle.js';
import { villageBonuses } from '../sim/clans.js';
import { armyHexAt, bandLand, forceSeed, garrisonOf, hexOnPath, scoutsIn, shareOf, spotChance, settlementScouts } from '../sim/enemyForces.js';
import { enemyHexAt, sightOf } from '../sim/enemyLands.js';
import { settlementLevel, settlementName } from '../sim/enemySettlements.js';
import { hexDistance, type Hex } from '../sim/hex.js';
import type { Land } from '../sim/land.js';
import { commandOf } from '../sim/lines.js';
import { roadRoute } from '../sim/logistics.js';
import type { Front } from '../sim/mapgen.js';
import { raidBattle } from '../sim/raids.js';
import { createRng } from '../sim/rng.js';
import { combatants, withIntel } from '../sim/scouting.js';
import { seasonAt, seasonDefense } from '../sim/seasons.js';
import type { PathStep } from '../sim/waves.js';
import { armyLand, armyLosses, sendHome } from './armies.js';
import { championsFall, championsOf, commandBonuses } from './champions.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';
import { generalAfterBattle } from './generals.js';
import { heroAfterBattle } from './heroes.js';
import { tell } from './notices.js';

const MS_PER_HOUR = 3_600_000;
const bandPayload = z.object({ bandId: z.number().int() });

const hoursMs = (hours: number, world: World) => (hours * MS_PER_HOUR) / world.speed;
const minuteOf = (at: Date) => Math.floor(at.getTime() / 60_000);

async function pending(client: DbClient, worldId: number, type: string): Promise<boolean> {
  const { rows } = await client.query("SELECT 1 FROM scheduled_events WHERE world_id = $1 AND type = $2 AND status = 'pending'", [worldId, type]);
  return rows.length > 0;
}

// The watch and the patrols on the calendar (from ensureEnemyLands).
export async function ensureEnemyForces(client: DbClient, data: GameData, world: World, now: Date): Promise<void> {
  const rules = data.enemyLands.forces;
  if (!(await pending(client, world.id, 'enemy_watch'))) await scheduleEvent(client, world.id, new Date(now.getTime() + hoursMs(rules.watchHours, world)), 'enemy_watch', {});
  if (!(await pending(client, world.id, 'enemy_patrol'))) await scheduleEvent(client, world.id, new Date(now.getTime() + hoursMs(rules.patrols.everyHours, world)), 'enemy_patrol', {});
}

// A war band's road (null: none), on the land its own walls don't stop.
function bandRoute(data: GameData, land: Land, world: World, from: Hex, to: Hex): PathStep[] | null {
  try {
    return roadRoute(data, land, from, to, data.enemyLands.forces.speed, world.speed);
  } catch {
    return null;
  }
}

export function bandHexAt(band: EnemyBand, at: Date): Hex {
  return hexOnPath(band.path, band.departsAt, at);
}

const levelOf = (data: GameData, world: World, s: EnemySettlement, at: Date) => settlementLevel(data, s.foundedAt, at, world.speed);

// Sets a band on a new road, leaving at `at`, and plans its arrival.
async function march(client: DbClient, world: World, band: EnemyBand, path: PathStep[], at: Date): Promise<EnemyBand> {
  const next = { ...band, path, departsAt: at, arrivesAt: new Date(at.getTime() + path.at(-1)!.atMs) };
  await saveEnemyBand(client, next);
  await scheduleEvent(client, world.id, next.arrivesAt, 'band_arrive', { bandId: band.id });
  return next;
}

// A band done with its errand: home to its settlement (a patrol: on to the next).
async function goHome(client: DbClient, data: GameData, world: World, band: EnemyBand, at: Date): Promise<void> {
  const cell = bandHexAt(band, at);
  const home = (await listEnemySettlements(client, world.id)).find((s) => s.id === band.settlementId);
  if (!home) return deleteEnemyBand(client, band.id);
  if (hexDistance(home.cell, cell) === 0) return arrivedHome(client, data, world, band, at);
  const path = bandRoute(data, bandLand(await armyLand(client, data, world)), world, cell, home.cell);
  if (!path) return deleteEnemyBand(client, band.id);
  await march(client, world, { ...band, status: 'returning', targetArmyId: null }, path, at);
}

async function arrivedHome(client: DbClient, data: GameData, world: World, band: EnemyBand, at: Date): Promise<void> {
  if (band.kind === 'sally') return deleteEnemyBand(client, band.id);
  await nextLeg(client, data, world, band, at);
}

// A patrol on to another settlement of its front, once it has rested
// (none left: it disbands).
async function nextLeg(client: DbClient, data: GameData, world: World, band: EnemyBand, at: Date): Promise<void> {
  const cell = bandHexAt(band, at);
  const others = (await listEnemySettlements(client, world.id)).filter((s) => s.front === band.front && hexDistance(s.cell, cell) > 0);
  if (!others.length) return deleteEnemyBand(client, band.id);
  const rng = createRng(forceSeed(world.seed, band.id, minuteOf(at)));
  const to = others[Math.floor(rng() * others.length)]!;
  const path = bandRoute(data, bandLand(await armyLand(client, data, world)), world, cell, to.cell);
  if (!path) return deleteEnemyBand(client, band.id);
  const leaves = new Date(at.getTime() + hoursMs(data.enemyLands.forces.patrols.restHours, world));
  await march(client, world, { ...band, status: 'patrolling', settlementId: to.id, targetArmyId: null }, path, leaves);
}

// The band catches the army: a battle where it stands. The army holds its
// ground (or falls); the band, if any is left, goes home.
async function bandBattle(client: DbClient, data: GameData, world: World, band: EnemyBand, army: Army, cell: Hex, at: Date): Promise<void> {
  const settlements = await listEnemySettlements(client, world.id);
  const home = settlements.find((s) => s.id === band.settlementId);
  const name = band.kind === 'sally' && home ? settlementName(data, home.front, home.kind) : 'Patrol';
  const stage = { stage: 1, name, stronghold: false, field: null, enemy: band.units };
  const village = await loadVillage(client, army.homeVillageId);
  const hero = await heroWithArmy(client, army.id);
  const general = await generalWithArmy(client, army.id);
  const owned = villageBonuses(data, village.state);
  const bonuses = commandBonuses(data, owned, hero, general);
  const succession = commandBonuses(data, owned, null, general);
  const fighters = combatants(data, army.units);
  const result = raidBattle(data, {
    army: fighters,
    armyStats: withIntel(data, army.units, playerStats(data, bonuses, false)),
    statsWithoutHero: withIntel(data, army.units, playerStats(data, succession, false)),
    champions: championsOf(data, hero, general, owned),
    armyStance: army.stance,
    stage,
    front: band.front as Front,
    seed: world.seed,
    season: seasonDefense(data, seasonAt(data, world, at).season),
    id: army.id * 8 + 5 + band.id * 64,
    lines: { attacker: commandOf(data, army.maneuver, [{ hero, general }]), defender: commandOf(data, 'encircle', []) },
  });
  const battle = await insertBattle(client, {
    worldId: world.id,
    waveId: null,
    villageId: null,
    q: cell.q,
    r: cell.r,
    setup: { raid: { front: band.front, name, stronghold: false, stage: 1, band: true } },
    attackerStance: data.raids.fieldStance,
    attackerInitial: band.units,
    defenderInitial: army.units,
    startedAt: at,
  });
  const kills = total(band.units) - total(result.enemyNow);
  const lost: Record<string, number> = {};
  for (const [unit, n] of Object.entries(fighters)) if (n - (result.armyNow[unit] ?? 0) > 0) lost[unit] = n - (result.armyNow[unit] ?? 0);
  // The army holds its hex with those left (none left: it is gone).
  const after = await armyLosses(client, data, world, army, lost, at);
  if (total(after.units) === 0) await sendHome(client, world, after, at, data);
  else await saveArmy(client, after);
  for (const [i, round] of result.rounds.entries()) {
    const log: RoundLog = {
      round: round.round,
      at: at.toISOString(),
      attackerLosses: round.defenderLosses,
      defenderLosses: round.attackerLosses,
      attackerLeft: round.defenderLeft,
      defenderLeft: round.attackerLeft,
    };
    await recordRound(client, battle.id, log, i === result.rounds.length - 1 ? { status: result.won ? 'defended' : 'raided', at, loot: null } : null);
  }
  await championsFall(client, data, world, result.fallen, { hero, general, homeVillageId: army.homeVillageId }, { kills, battleId: battle.id, at });
  if (hero && !result.fallen.includes('hero')) await heroAfterBattle(client, data, world, hero, { kills, won: result.won, battleId: battle.id, at });
  if (general && !result.fallen.includes('general')) await generalAfterBattle(client, data, world, general, { kills, won: result.won, at });
  if (total(result.enemyNow) === 0) await deleteEnemyBand(client, band.id);
  else await goHome(client, data, world, { ...band, units: result.enemyNow }, at);
  await tell(client, world, army.ownerAccountId, {
    kind: 'battle_result',
    tier: 'push',
    title: result.won ? 'Your army beat off a war band at ({q}, {r})' : 'A war band mauled your army at ({q}, {r})',
    body: '{kills} of them fell, {lost} of ours.',
    vars: { q: cell.q, r: cell.r, kills, lost: total(lost) },
  }, at);
  await notifyWorld(client, { worldId: world.id, type: 'armies' });
}

export const enemyForceHandlers: HandlerRegistry = {
  // The enemy's scouts look for armies in their lands.
  async enemy_watch({ client, data, world }, event) {
    if (world.status !== 'running') return;
    const at = event.dueAt;
    const rules = data.enemyLands.forces;
    await scheduleEvent(client, world.id, new Date(at.getTime() + hoursMs(rules.watchHours, world)), 'enemy_watch', {});
    // Only armies in the enemy lands are looked for.
    const armies = (await listArmies(client, world.id))
      .filter((a) => a.status !== 'done' && !a.raid)
      .filter((a) => {
        const cell = armyHexAt(a, at);
        return !!cell && !!enemyHexAt(data, cell, world);
      })
      .sort((x, y) => x.id - y.id);
    if (!armies.length) return;
    const settlements = await listEnemySettlements(client, world.id);
    let bands = await listEnemyBands(client, world.id);
    const players = (await listMembers(client, world.id)).length;
    let land: Land | null = null;
    for (const army of armies) {
      const cell = armyHexAt(army, at);
      const where = cell ? enemyHexAt(data, cell, world) : null;
      if (!cell || !where) continue;
      if (bands.some((b) => b.status === 'hunting' && b.targetArmyId === army.id)) continue;
      const guards = scoutsIn(data, army.units);
      const rng = createRng(forceSeed(world.seed, army.id, minuteOf(at)));
      const watchers = [
        ...settlements.filter((s) => s.front === where.front && hexDistance(s.cell, cell) <= rules.sightRange).map((s) => settlementScouts(data, levelOf(data, world, s, at))),
        ...bands.filter((b) => b.front === where.front && hexDistance(bandHexAt(b, at), cell) <= rules.sightRange).map((b) => b.scouts),
      ];
      let spotted = false;
      for (const scouts of watchers) {
        if (rng() < spotChance(data, scouts, guards)) spotted = true;
      }
      if (!spotted) continue;
      land ??= bandLand(await armyLand(client, data, world));
      let sent = 0;
      // A sally from the nearest settlement that can.
      const ready = settlements
        .filter((s) => s.front === where.front && hexDistance(s.cell, cell) <= rules.pullRange && (!s.sallyReadyAt || s.sallyReadyAt.getTime() <= at.getTime()))
        .sort((x, y) => hexDistance(x.cell, cell) - hexDistance(y.cell, cell) || x.id - y.id)[0];
      if (ready) {
        const path = bandRoute(data, land, world, ready.cell, cell);
        if (path) {
          const units = shareOf(garrisonOf(data, ready, levelOf(data, world, ready, at), world.seed, players), rules.sally.share);
          const band: Omit<EnemyBand, 'id'> = { front: ready.front, kind: 'sally', settlementId: ready.id, units, scouts: 1, status: 'hunting', path, departsAt: at, arrivesAt: new Date(at.getTime() + path.at(-1)!.atMs), targetArmyId: army.id };
          const id = await insertEnemyBand(client, world.id, band);
          await scheduleEvent(client, world.id, band.arrivesAt, 'band_arrive', { bandId: id });
          await setSallyReady(client, ready.id, new Date(at.getTime() + hoursMs(rules.sally.cooldownHours, world)));
          ready.sallyReadyAt = new Date(at.getTime() + hoursMs(rules.sally.cooldownHours, world));
          bands.push({ ...band, id });
          sent++;
        }
      }
      // And the front's patrols near it.
      for (const b of [...bands]) {
        if (b.front !== where.front || b.kind !== 'patrol' || b.status !== 'patrolling') continue;
        const from = bandHexAt(b, at);
        if (hexDistance(from, cell) > rules.pullRange) continue;
        const path = bandRoute(data, land, world, from, cell);
        if (!path) continue;
        const next = await march(client, world, { ...b, status: 'hunting', targetArmyId: army.id }, path, at);
        bands = bands.map((o) => (o.id === b.id ? next : o));
        sent++;
      }
      if (sent) {
        await tell(client, world, army.ownerAccountId, {
          kind: 'under_attack',
          tier: 'push',
          title: 'Enemy scouts spotted your army at ({q}, {r})',
          body: '{bands} war band(s) of the {faction} march on it.',
          vars: { q: cell.q, r: cell.r, bands: sent, faction: data.enemies.fronts[where.front]?.faction ?? where.front },
        }, at);
      }
    }
    await notifyWorld(client, { worldId: world.id, type: 'world' });
  },

  // Each front keeps its patrols marching between its settlements.
  async enemy_patrol({ client, data, world }, event) {
    if (world.status !== 'running') return;
    const at = event.dueAt;
    const rules = data.enemyLands.forces;
    await scheduleEvent(client, world.id, new Date(at.getTime() + hoursMs(rules.patrols.everyHours, world)), 'enemy_patrol', {});
    const settlements = await listEnemySettlements(client, world.id);
    const bands = await listEnemyBands(client, world.id);
    const players = (await listMembers(client, world.id)).length;
    let land: Land | null = null;
    for (const [i, front] of world.activeFronts.entries()) {
      const own = settlements.filter((s) => s.front === front);
      if (own.length < 2 || bands.filter((b) => b.front === front && b.kind === 'patrol').length >= rules.patrols.perFront) continue;
      const rng = createRng(forceSeed(world.seed, i + 1, minuteOf(at)));
      const home = own[Math.floor(rng() * own.length)]!;
      const others = own.filter((s) => s.id !== home.id);
      const to = others[Math.floor(rng() * others.length)]!;
      land ??= bandLand(await armyLand(client, data, world));
      const path = bandRoute(data, land, world, home.cell, to.cell);
      if (!path) continue;
      const units = shareOf(garrisonOf(data, home, levelOf(data, world, home, at), world.seed, players), rules.patrols.share);
      const band: Omit<EnemyBand, 'id'> = { front, kind: 'patrol', settlementId: to.id, units, scouts: rules.patrols.scouts, status: 'patrolling', path, departsAt: at, arrivesAt: new Date(at.getTime() + path.at(-1)!.atMs), targetArmyId: null };
      const id = await insertEnemyBand(client, world.id, band);
      await scheduleEvent(client, world.id, band.arrivesAt, 'band_arrive', { bandId: id });
    }
    await notifyWorld(client, { worldId: world.id, type: 'world' });
  },

  async band_arrive({ client, data, world }, event) {
    const { bandId } = bandPayload.parse(event.payload);
    const band = await loadEnemyBand(client, bandId);
    const at = event.dueAt;
    if (!band || band.arrivesAt.getTime() !== at.getTime() || world.status !== 'running') return;
    const cell = bandHexAt(band, at);
    if (band.status === 'hunting') {
      const army = band.targetArmyId !== null ? await loadArmy(client, band.targetArmyId).catch(() => null) : null;
      const armyCell = army && army.status !== 'done' && !army.raid ? armyHexAt(army, at) : null;
      if (army && armyCell && hexDistance(armyCell, cell) <= 1) {
        await bandBattle(client, data, world, band, army, armyCell, at);
      } else if (armyCell && enemyHexAt(data, armyCell, world) && hexDistance(armyCell, cell) <= data.enemyLands.forces.sally.chaseRange) {
        // It gives chase.
        const path = bandRoute(data, bandLand(await armyLand(client, data, world)), world, cell, armyCell);
        if (path) await march(client, world, band, path, at);
        else await goHome(client, data, world, band, at);
      } else {
        await goHome(client, data, world, band, at);
      }
    } else if (band.status === 'patrolling') {
      await nextLeg(client, data, world, band, at);
    } else {
      await arrivedHome(client, data, world, band, at);
    }
    await notifyWorld(client, { worldId: world.id, type: 'world' });
  },
};

// map.bands: the war bands the players see (those hunting, and those in
// bands of their lands already seen).
export function bandsView(data: GameData, world: World, bands: readonly EnemyBand[], at: Date): unknown[] {
  return bands
    .filter((b) => {
      if (b.status === 'hunting') return true;
      const where = enemyHexAt(data, bandHexAt(b, at), world);
      return !!where && where.band <= sightOf(data, world, where.front);
    })
    .map((b) => ({
      id: b.id,
      front: b.front,
      kind: b.kind,
      status: b.status,
      units: b.units,
      targetArmyId: b.targetArmyId,
      departsAt: b.departsAt.toISOString(),
      arrivesAt: b.arrivesAt.toISOString(),
      path: b.path.map((s) => [s.q, s.r, s.atMs]),
    }));
}

