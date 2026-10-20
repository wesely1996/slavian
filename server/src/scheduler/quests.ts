// Hero quests on the scheduler (sim/quests.ts): a quest sends the hero away
// (status 'questing') and hero_quest brings it home with what it went for.
import type { GameData } from '../data/index.js';
import { RuleError } from '../errors.js';
import { loadHero, saveHero, type Hero } from '../db/heroes.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { insertMission, markMissionDone, recordReport } from '../db/scouting.js';
import { listSites, listScrolls, loadSite } from '../db/sites.js';
import { loadVillage, saveVillageState } from '../db/villages.js';
import type { World } from '../db/worlds.js';
import { total } from '../sim/battle.js';
import { gainXp, woundMs } from '../sim/heroes.js';
import { hex } from '../sim/hex.js';
import { receive } from '../sim/logistics.js';
import type { Front } from '../sim/mapgen.js';
import { caravanFind, questMs, questOffers, questWounds, questXp, type QuestOffer, type QuestWorld } from '../sim/quests.js';
import { createRng } from '../sim/rng.js';
import { scoutReport } from '../sim/scouting.js';
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
  const { rows } = await client.query<{ front: Front }>(
    "SELECT DISTINCT front FROM waves WHERE world_id = $1 AND status = 'scheduled' ORDER BY front",
    [world.id],
  );
  const sites = (await listSites(client, world.id)).filter((s) => s.status === 'unexplored' && total(s.guardians) === 0);
  const owned = new Set([...hero.inventory, ...Object.values(hero.gear)]);
  return {
    seed: world.seed,
    speed: world.speed,
    startedAt: world.startedAt ?? new Date(0),
    fronts: rows.map((r) => r.front),
    sites: sites.map((s) => ({ id: s.id, q: s.q, r: s.r })),
    gearLeft: Object.keys(data.heroes.items).some((item) => !owned.has(item)),
  };
}

// The quests the hero is offered now (none while it is away or has no home).
export async function heroQuestOffers(client: DbClient, data: GameData, world: World, hero: Hero, at: Date): Promise<QuestOffer[]> {
  if (hero.villageId === null || world.status !== 'running') return [];
  const home = await loadVillage(client, hero.villageId);
  return questOffers(data, await questWorld(client, data, world, hero), hero, hex(home.q, home.r), at, hero.questsDone);
}

// Sends the hero on one of its offers.
export async function startQuest(client: DbClient, data: GameData, world: World, hero: Hero, offerId: string, at: Date): Promise<Hero> {
  if (hero.status !== 'home') throw new RuleError(`${hero.name} must be at home, unhurt, to set out`);
  const home = await loadVillage(client, hero.villageId!);
  if (home.state.besieged) throw new RuleError(`${hero.name} won't leave ${home.name} in the middle of a battle`);
  const offer = (await heroQuestOffers(client, data, world, hero, at)).find((o) => o.id === offerId);
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

// The next horde from a front that hasn't set out yet.
async function nextWave(client: DbClient, worldId: number, front: Front | null) {
  const { rows } = await client.query<{ id: number; composition: Record<string, number>; stance: string; front: Front }>(
    `SELECT id, composition, stance, front FROM waves WHERE world_id = $1 AND front = $2 AND status = 'scheduled'
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
      await client.query(
        `UPDATE scheduled_events SET due_at = due_at + make_interval(secs => $3::double precision / 1000)
         WHERE world_id = $1 AND status = 'pending' AND type IN ('wave_spawn', 'wave_warning') AND (payload->>'waveId')::bigint = $2`,
        [world.id, wave.id, delay],
      );
      await notifyWorld(client, { worldId: world.id, type: 'waves' });
      return { body: 'The next horde from the {front} sets out {hours} game hours later.', vars: { front: quest.front ?? '', hours: data.quests.kinds.ambush.delayHours ?? 0 } };
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
      await recordReport(client, mission.id, report);
      await markMissionDone(client, mission.id);
      await notifyWorld(client, { worldId: world.id, type: 'scouting' });
      return { body: 'A full report on the next horde from the {front} is in the threats panel.', vars: { front: quest.front ?? '' } };
    }
    case 'caravan': {
      const found = caravanFind(data, hero.level);
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
    if (hero.status !== 'questing' || !quest || new Date(quest.returnsAt) > event.dueAt) return;
    const told = await fulfil(client, data, world, hero, quest, event.dueAt);
    // Finds may have changed the hero (gear); start from what is stored.
    const after = await loadHero(client, world.id, accountId);
    const wounded = questWounds(quest, world.seed, accountId, new Date(quest.departsAt));
    let back: Hero = { ...after, ...gainXp(data, after, questXp(data, quest, after.kind)), status: 'home', quest: null };
    if (wounded) {
      const woundedUntil = new Date(event.dueAt.getTime() + woundMs(data, world.speed, after.kind));
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
  },
};
