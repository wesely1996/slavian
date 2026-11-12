// Hero quests on the scheduler (sim/quests.ts): a quest sends the hero away
// (status 'questing') and hero_quest brings it home with what it went for.
import { achieve } from './achievements.js';
import { angerFront } from './waves.js';
import type { GameData } from '../data/index.js';
import { RuleError } from '../errors.js';
import { loadHero, saveHero, type Hero } from '../db/heroes.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { insertMission, markMissionDone, recordReport } from '../db/scouting.js';
import { listSites, listScrolls, loadSite } from '../db/sites.js';
import { loadVillage, saveVillageState } from '../db/villages.js';
import { getWorld, type World } from '../db/worlds.js';
import { total } from '../sim/battle.js';
import { gainXp, woundMs } from '../sim/heroes.js';
import { hallLevelAt } from './generals.js';
import { hex } from '../sim/hex.js';
import { receive } from '../sim/logistics.js';
import type { Front } from '../sim/mapgen.js';
import {
  armyQuestMark,
  armyQuestOffers,
  armyQuestUnits,
  caravanFind,
  parseArmyQuestMark,
  questFind,
  questMs,
  questOffers,
  questSlot,
  questWounds,
  questXp,
  type ArmyQuestOffer,
  type QuestOffer,
  type QuestWorld,
} from '../sim/quests.js';
import type { ArmyQuestKind } from '../data/index.js';
import { loadArmy } from '../db/armies.js';
import { insertQuestSite } from '../db/sites.js';
import { lastWave } from '../db/waves.js';
import { listMembers, loadHexes } from '../db/worlds.js';
import { questCell } from '../sim/bridge.js';
import { composeWave } from '../sim/waves.js';
import { moveArmy } from './armies.js';
import { createCamp, occupiedHexes } from './camps.js';
import { createRng } from '../sim/rng.js';
import { combatants, scoutReport } from '../sim/scouting.js';
import { distanceShare, rollFind } from '../sim/sites.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';
import { heroPayload, type HeroPayload } from './heroes.js';
import { tell } from './notices.js';
import { claimFind } from './sites.js';

const MS_PER_HOUR = 3_600_000;
// Offers a hero remembers having taken (older ones can't come back anyway).
const DONE_KEPT = 30;

// What the world holds for the hero's quests right now.
async function questWorld(client: DbClient, data: GameData, world: World, hero: Hero): Promise<QuestWorld> {
  // Each front with a horde yet to set out, and how much the front hates already.
  const { rows } = await client.query<{ front: Front }>(
    "SELECT DISTINCT front FROM waves WHERE world_id = $1 AND status = 'scheduled' AND band_of IS NULL ORDER BY front",
    [world.id],
  );
  const sites = (await listSites(client, world.id)).filter((s) => s.status === 'unexplored' && total(s.guardians) === 0);
  const owned = new Set([...hero.inventory, ...Object.values(hero.gear)]);
  return {
    seed: world.seed,
    speed: world.speed,
    startedAt: world.startedAt ?? new Date(0),
    fronts: rows.map((r) => r.front),
    hatred: Object.fromEntries(rows.map((r) => [r.front, Number(world.hatred[r.front] ?? 0)])),
    sites: sites.map((s) => ({ id: s.id, q: s.q, r: s.r })),
    gearLeft: Object.keys(data.heroes.items).some((item) => !owned.has(item)),
  };
}

// The quests the hero is offered now (none while it has no home). Leading
// an army standing in the field, with no army quest on, it is offered army
// quests instead.
export async function heroQuestOffers(client: DbClient, data: GameData, world: World, hero: Hero, at: Date): Promise<(QuestOffer | ArmyQuestOffer)[]> {
  if (world.status !== 'running') return [];
  if (hero.status === 'with_army') {
    if (hero.armyId === null || (await loadArmy(client, hero.armyId)).status !== 'stationed') return [];
    if (await armyQuestOf(client, world.id, hero.accountId)) return [];
    return armyQuestOffers(data, { seed: world.seed, speed: world.speed, startedAt: world.startedAt ?? new Date(0) }, hero, at, hero.questsDone);
  }
  if (hero.villageId === null) return [];
  const home = await loadVillage(client, hero.villageId);
  return questOffers(data, await questWorld(client, data, world, hero), hero, hex(home.q, home.r), at, hero.questsDone);
}

// The army quest the hero is on: its place, and when it is gone.
export interface ArmyQuest {
  readonly kind: ArmyQuestKind;
  readonly q: number;
  readonly r: number;
  readonly endsAt: string | null;
}

export async function armyQuestOf(client: DbClient, worldId: number, accountId: number): Promise<ArmyQuest | null> {
  const { rows } = await client.query<{ quest: string; q: number; r: number; ends_at: Date | null }>(
    `SELECT quest, q, r, ends_at FROM camps WHERE world_id = $1 AND status = 'active' AND quest LIKE $2
     UNION ALL SELECT quest, q, r, ends_at FROM sites WHERE world_id = $1 AND status = 'unexplored' AND quest LIKE $2
     ORDER BY q, r LIMIT 1`,
    [worldId, `hero:${accountId}:%`],
  );
  const row = rows[0];
  const mark = parseArmyQuestMark(row?.quest);
  if (!row || !mark) return null;
  return { kind: mark.kind, q: row.q, r: row.r, endsAt: row.ends_at?.toISOString() ?? null };
}

// The hero takes its army on an army quest: the quest's place is raised
// near the army, and the army marches on it.
async function startArmyQuest(client: DbClient, data: GameData, world: World, hero: Hero, offerId: string, at: Date): Promise<Hero> {
  if (hero.status !== 'with_army' || hero.armyId === null) throw new RuleError(`${hero.name} must lead an army to take it on that quest`);
  const army = await loadArmy(client, hero.armyId);
  if (army.status !== 'stationed') throw new RuleError(`${hero.name}'s army must stand in the field to set out`);
  if (total(combatants(data, army.units)) === 0) throw new RuleError(`${hero.name}'s army has nobody to fight`);
  if (await armyQuestOf(client, world.id, hero.accountId)) throw new RuleError(`${hero.name} is already on a quest with the army`);
  const offer = (await heroQuestOffers(client, data, world, hero, at)).find((o) => o.id === offerId);
  if (!offer || !('army' in offer)) throw new RuleError('That quest is no longer on offer');
  const def = data.quests.army.kinds[offer.kind];
  const seed = (world.seed ^ Math.imul(hero.accountId + 1, 0x632be5ab) ^ questSlot(data, { startedAt: world.startedAt ?? new Date(0), speed: world.speed }, at)) >>> 0;
  const terrain = new Map((await loadHexes(client, world.id)).map(([q, r, t]) => [`${q},${r}`, t] as const));
  const cell = questCell(data, terrain, await occupiedHexes(client, world.id), seed, def.minDistance, def.maxDistance, hex(army.targetQ, army.targetR));
  if (!cell) throw new RuleError('There is no place for that quest anywhere near the army');
  const fronts = world.activeFronts;
  const front = fronts[seed % fronts.length]! as Front;
  const last = await lastWave(client, world.id);
  const players = (await listMembers(client, world.id)).length;
  const units = composeWave(data, front, Math.max(1, last?.index ?? 1), armyQuestUnits(data, offer.kind, hero.level), seed, players);
  const endsAt = new Date(at.getTime() + (def.lastsHours * MS_PER_HOUR) / world.speed);
  const mark = armyQuestMark(hero.accountId, offer.kind);
  if (offer.kind === 'barrow') {
    const siteId = await insertQuestSite(client, world.id, { kind: 'kurgan', q: cell.q, r: cell.r, guardians: units }, mark, endsAt);
    await scheduleEvent(client, world.id, endsAt, 'map_event_end', { siteId });
  } else {
    const reward = def.resources ? { resources: questFind(data, def.resources, hero.level) } : null;
    const camp = await createCamp(
      client,
      data,
      world,
      { kind: offer.kind === 'warlord' ? 'lair' : 'bandit', front, q: cell.q, r: cell.r, units, waveId: null, reward, endsAt, quest: mark },
      at,
    );
    await scheduleEvent(client, world.id, endsAt, 'map_event_end', { campId: camp.id });
  }
  const next: Hero = { ...hero, questsDone: [...hero.questsDone, offer.id].slice(-DONE_KEPT) };
  await saveHero(client, next);
  await moveArmy(client, data, world, army, { hex: cell }, at);
  await notifyWorld(client, { worldId: world.id, type: 'heroes' });
  await notifyWorld(client, { worldId: world.id, type: 'world' });
  return next;
}

// An army quest's place cleared (or searched): its hero gets the XP.
export async function armyQuestDone(client: DbClient, data: GameData, world: World, mark: string | null | undefined, at: Date): Promise<void> {
  const quest = parseArmyQuestMark(mark);
  if (!quest) return;
  const hero = await loadHero(client, world.id, quest.accountId);
  const def = data.quests.army.kinds[quest.kind];
  await saveHero(client, { ...hero, ...gainXp(data, hero, questXp(data, def, hero.kind)) });
  await notifyWorld(client, { worldId: world.id, type: 'heroes' });
  await tell(client, world, quest.accountId, {
    kind: 'hero',
    tier: 'digest',
    title: '{name} has done: {quest}',
    body: 'The army quest is done: {xp} XP for {name}.',
    vars: { name: hero.name, quest: def.name, xp: questXp(data, def, hero.kind) },
  }, at);
  await achieve(client, data, world, quest.accountId, 'army_quest', at);
}

// An army quest's place gone, not done in time: its hero hears of it.
// Returns whether it was one.
export async function armyQuestGone(client: DbClient, data: GameData, world: World, mark: string | null | undefined, at: Date): Promise<boolean> {
  const quest = parseArmyQuestMark(mark);
  if (!quest) return false;
  const hero = await loadHero(client, world.id, quest.accountId);
  await notifyWorld(client, { worldId: world.id, type: 'heroes' });
  await tell(client, world, quest.accountId, {
    kind: 'hero',
    tier: 'digest',
    title: '{name} failed: {quest}',
    body: 'The army did not get there in time, and the chance is gone.',
    vars: { name: hero.name, quest: data.quests.army.kinds[quest.kind].name },
  }, at);
  return true;
}

// Sends the hero on one of its offers.
export async function startQuest(client: DbClient, data: GameData, world: World, hero: Hero, offerId: string, at: Date): Promise<Hero> {
  if (offerId.includes(':army:')) return startArmyQuest(client, data, world, hero, offerId, at);
  if (hero.status !== 'home') throw new RuleError(`${hero.name} must be at home, unhurt, to set out`);
  const home = await loadVillage(client, hero.villageId!);
  if (home.state.besieged) throw new RuleError(`${hero.name} won't leave ${home.name} in the middle of a battle`);
  const offer = (await heroQuestOffers(client, data, world, hero, at)).find((o): o is QuestOffer => o.id === offerId && !('army' in o));
  if (!offer) throw new RuleError('That quest is no longer on offer');
  const returnsAt = new Date(at.getTime() + questMs(offer, world.speed));
  const away: Hero = {
    ...hero,
    status: 'questing',
    quest: { ...offer, departsAt: at.toISOString(), returnsAt: returnsAt.toISOString() },
    questsDone: [...hero.questsDone, offer.id].slice(-DONE_KEPT),
  };
  await saveHero(client, away);
  const payload: HeroPayload = { accountId: hero.accountId };
  await scheduleEvent(client, world.id, returnsAt, 'hero_quest', payload);
  await notifyWorld(client, { worldId: world.id, type: 'heroes' });
  return away;
}

// The quest called off: the hero turns for home where it is (on the way
// there it comes back as far as it went; at the place, from there) and
// brings nothing back. One already on the way home can't call it off.
export async function cancelQuest(client: DbClient, data: GameData, world: World, hero: Hero, at: Date): Promise<Hero> {
  const quest = hero.quest;
  if (hero.status !== 'questing' || !quest) throw new RuleError(`${hero.name} is on no quest`);
  if (quest.cancelled) throw new RuleError(`${hero.name} is already on the way home`);
  const elapsed = at.getTime() - new Date(quest.departsAt).getTime();
  const roadHours = (quest.hours - data.quests.kinds[quest.kind].hours) / 2;
  const outMs = questMs({ hours: roadHours }, world.speed);
  const homeward = new Date(quest.returnsAt).getTime() - outMs;
  if (at.getTime() >= homeward) throw new RuleError(`${hero.name} is already on the way home`);
  const returnsAt = new Date(at.getTime() + Math.min(elapsed, outMs));
  const turned: Hero = { ...hero, quest: { ...quest, cancelled: true, returnsAt: returnsAt.toISOString() } };
  await saveHero(client, turned);
  const payload: HeroPayload = { accountId: hero.accountId };
  await scheduleEvent(client, world.id, returnsAt, 'hero_quest', payload);
  await notifyWorld(client, { worldId: world.id, type: 'heroes' });
  return turned;
}

// The next horde from a front that hasn't set out yet.
async function nextWave(client: DbClient, worldId: number, front: Front | null) {
  const { rows } = await client.query<{ id: number; composition: Record<string, number>; stance: string; front: Front; hatred: number }>(
    `SELECT id, composition, stance, front, hatred FROM waves WHERE world_id = $1 AND front = $2 AND status = 'scheduled' AND band_of IS NULL
     ORDER BY spawn_at, id LIMIT 1`,
    [worldId, front],
  );
  return rows[0] ?? null;
}

// What the hero has to tell: a notice body and its words.
type Told = { body: string; vars?: Record<string, string | number> };

// Does what the quest set out to do.
async function fulfil(client: DbClient, data: GameData, world: World, hero: Hero, quest: NonNullable<Hero["quest"]>, at: Date): Promise<Told> {
  const home = await loadVillage(client, hero.villageId!);
  switch (quest.kind) {
    case 'ambush': {
      const wave = await nextWave(client, world.id, quest.front);
      if (!wave) return { body: 'The road lay empty: that horde had already set out.' };
      const delay = Math.round(((data.quests.kinds.ambush.delayHours ?? 0) * MS_PER_HOUR) / world.speed);
      await client.query(`UPDATE waves SET spawn_at = spawn_at + make_interval(secs => $2::double precision / 1000) WHERE id = $1`, [wave.id, delay]);
      // Held up, its front hates the more.
      const hatred = Number((await getWorld(client, world.id)).hatred[wave.front] ?? 0) + data.horde.hatred.perAmbush;
      await angerFront(client, data, world, wave.front, data.horde.hatred.perAmbush, at);
      await client.query(
        `UPDATE scheduled_events SET due_at = due_at + make_interval(secs => $3::double precision / 1000)
         WHERE world_id = $1 AND status = 'pending' AND type IN ('wave_spawn', 'wave_warning') AND (payload->>'waveId')::bigint = $2`,
        [world.id, wave.id, delay],
      );
      await notifyWorld(client, { worldId: world.id, type: 'waves' });
      // Told in real minutes, at any world speed.
      return { body: 'The next horde from the {front} sets out {minutes} minutes later, hating you the more: +{hatred}% attack and defense.', vars: { front: quest.front ?? '', minutes: Math.round(delay / 60_000), hatred: Math.round(hatred * 100) } };
    }
    case 'scout': {
      const wave = await nextWave(client, world.id, quest.front);
      if (!wave) return { body: 'That horde had already set out; the hero saw only its dust.' };
      const best = [...data.scouting.tiers].sort((a, b) => b.minSurvivors - a.minSurvivors)[0]!;
      const mission = await insertMission(client, {
        worldId: world.id,
        villageId: home.id,
        waveId: wave.id,
        sent: best.minSurvivors,
        units: { scout: best.minSurvivors },
        target: { q: home.q, r: home.r },
        departsAt: new Date(quest.departsAt),
        arrivesAt: at,
        returnsAt: at,
      });
      const report = scoutReport(data, {
        front: wave.front,
        composition: wave.composition,
        stance: wave.stance as never,
        sent: best.minSurvivors,
        survivors: best.minSurvivors,
        dispersed: false,
        seed: world.seed,
        missionId: mission.id,
      });
      await recordReport(client, mission.id, report, { scout: best.minSurvivors });
      await markMissionDone(client, mission.id);
      await notifyWorld(client, { worldId: world.id, type: 'scouting' });
      return { body: 'A full report on the next horde from the {front} is in the threats panel.', vars: { front: quest.front ?? '' } };
    }
    case 'shrine':
      return { body: 'Kept vigil under the oak, and came back wiser.' };
    case 'caravan':
    case 'hunt':
    case 'tribute': {
      const found = quest.kind === 'caravan' ? caravanFind(data, hero.level) : questFind(data, data.quests.kinds[quest.kind].resources, hero.level);
      const { ledger } = receive(home.state.ledger, at, found);
      await saveVillageState(client, home.id, { ...home.state, ledger });
      await notifyWorld(client, { worldId: world.id, type: 'village', villageId: home.id });
      return { body: 'Brought back {wood} wood, {stone} stone, {grain} grain and {iron} iron.', vars: found };
    }
    case 'hoard': {
      const owned = new Set([...hero.inventory, ...Object.values(hero.gear)]);
      const left = Object.keys(data.heroes.items).filter((i) => !owned.has(i)).sort();
      if (!left.length) return { body: 'The hoard had been dug up already.' };
      const item = left[Math.floor(createRng((world.seed ^ Math.imul(hero.accountId + 1, 0x165667b1) ^ left.length) >>> 0)() * left.length)]!;
      await saveHero(client, { ...hero, inventory: [...hero.inventory, item] });
      return { body: 'Found the {item}.', vars: { item: data.heroes.items[item]!.name } };
    }
    case 'ruins': {
      const site = quest.siteId === null ? null : await loadSite(client, quest.siteId);
      if (!site || site.status === 'explored' || total(site.guardians) > 0) return { body: 'Someone had been there first.' };
      const find = rollFind(data, {
        kind: site.kind,
        seed: world.seed,
        siteId: site.id,
        distance: distanceShare(hex(site.q, site.r), world.radius ?? 0),
      lootFactor: site.hard ? data.events.kinds.ruin.lootFactor : 1,
        foundScrolls: new Set((await listScrolls(client, world.id)).map((s) => s.scroll)),
        ownedGear: new Set([...hero.inventory, ...Object.values(hero.gear)]),
      });
      if (find.type === 'resources') {
        const { ledger } = receive(home.state.ledger, at, find.resources);
        await saveVillageState(client, home.id, { ...home.state, ledger });
        await notifyWorld(client, { worldId: world.id, type: 'village', villageId: home.id });
      }
      await claimFind(client, data, world, site, hero.accountId, hero, find, at);
      return { body: 'Searched the {site}.', vars: { site: data.sites.kinds[site.kind]?.name ?? 'site' } };
    }
  }
}

export const questHandlers: HandlerRegistry = {
  async hero_quest({ client, data, world }, event) {
    const { accountId } = heroPayload.parse(event.payload);
    const hero = await loadHero(client, world.id, accountId);
    const quest = hero.quest;
    // (A quest called off comes home earlier: its old return does nothing.)
    if (hero.status !== 'questing' || !quest || new Date(quest.returnsAt).getTime() !== event.dueAt.getTime()) return;
    if (quest.cancelled) {
      await saveHero(client, { ...hero, status: 'home', quest: null });
      await notifyWorld(client, { worldId: world.id, type: 'heroes' });
      return;
    }
    const told = await fulfil(client, data, world, hero, quest, event.dueAt);
    // Finds may have changed the hero (gear); start from what is stored.
    const after = await loadHero(client, world.id, accountId);
    const wounded = questWounds(quest, world.seed, accountId, new Date(quest.departsAt));
    let back: Hero = { ...after, ...gainXp(data, after, questXp(data, quest, after.kind)), status: 'home', quest: null };
    if (wounded) {
      const woundedUntil = new Date(event.dueAt.getTime() + woundMs(data, world.speed, after.kind, await hallLevelAt(client, after.villageId)));
      back = { ...back, status: 'wounded', woundedUntil };
      const payload: HeroPayload = { accountId };
      await scheduleEvent(client, world.id, woundedUntil, 'hero_recover', payload);
    }
    await saveHero(client, back);
    await notifyWorld(client, { worldId: world.id, type: 'heroes' });
    await tell(client, world, accountId, {
      kind: 'hero',
      tier: 'digest',
      title: wounded ? '{name} came back wounded from: {quest}' : '{name} is back from: {quest}',
      body: told.body,
      vars: { ...told.vars, name: hero.name, quest: data.quests.kinds[quest.kind].name },
    }, event.dueAt);
    await achieve(client, data, world, accountId, 'hero_quest', event.dueAt);
  },
};
