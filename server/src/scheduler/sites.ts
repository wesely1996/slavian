// Ancient sites on the scheduler (PLAN.md §8.1): an army sent to explore
// fights the site's guardians on arrival, searches for a while
// (site_explored) and comes home with what it found. Lore scrolls serve the
// whole group (research.ts refreshBonuses).
import { z } from 'zod';
import type { GameData } from '../data/index.js';
import { loadArmy, saveArmy, type Army } from '../db/armies.js';
import { insertBattle, recordRound, type RoundLog } from '../db/battles.js';
import { heroWithArmy, loadHero, saveHero } from '../db/heroes.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { addScroll, listScrolls, listSites, loadSite, markExplored, saveGuardians, siteAt, insertSites } from '../db/sites.js';
import { listVillages, loadVillage } from '../db/villages.js';
import { addEmbers, listMembers, loadHexes, type World } from '../db/worlds.js';
import { playerStats, total } from '../sim/battle.js';
import { assault } from '../sim/camps.js';
import { combine, heroBonuses } from '../sim/heroes.js';
import { hex } from '../sim/hex.js';
import { distanceShare, placeSites, rollFind, type Find } from '../sim/sites.js';
import { armyLosses, sendHome } from './armies.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';
import { heroAfterBattle } from './heroes.js';
import { tell } from './notices.js';
import { refreshBonuses } from './research.js';
import { bridgeQuest } from './bridge.js';

const MS_PER_HOUR = 3_600_000;

export const explorePayload = z.object({ armyId: z.number().int(), siteId: z.number().int() });
export type ExplorePayload = z.infer<typeof explorePayload>;

// Places the ancient sites of a world that has none yet.
export async function ensureSites(client: DbClient, data: GameData, world: World): Promise<void> {
  if (world.radius === null || (await listSites(client, world.id)).length) return;
  const terrain = new Map((await loadHexes(client, world.id)).map(([q, r, t]) => [`${q},${r}`, t] as const));
  const villages = (await listVillages(client, world.id)).map((v) => hex(v.q, v.r));
  const players = (await listMembers(client, world.id)).length;
  await insertSites(client, world.id, placeSites(data, { terrain, radius: world.radius, startSites: villages, seed: world.seed, players }));
}

export function findText(data: GameData, find: Find): string {
  switch (find.type) {
    case 'resources':
      return `${Object.values(find.resources).reduce((a, b) => a + b, 0)} resources`;
    case 'gear':
      return data.heroes.items[find.item]?.name ?? find.item;
    case 'ember':
      return "a Svarog's Ember";
    case 'scroll':
      return `the scroll "${data.lore.scrolls[find.scroll]?.name ?? find.scroll}"`;
  }
}

// An army sent to explore has reached the site.
export async function arriveAtSite(client: DbClient, data: GameData, world: World, army: Army, at: Date): Promise<void> {
  const site = await siteAt(client, world.id, army.targetQ, army.targetR);
  if (!site || site.status === 'explored') {
    await sendHome(client, world, army, at, data);
    return;
  }
  let explorers = army;
  if (total(site.guardians) > 0) {
    const home = await loadVillage(client, army.homeVillageId);
    const hero = await heroWithArmy(client, army.id);
    const bonuses = hero ? combine(home.state.bonuses, heroBonuses(data, hero)) : home.state.bonuses;
    const result = assault(data, {
      army: army.units,
      armyStats: playerStats(data, bonuses, false),
      armyStance: home.state.stance,
      camp: site.guardians,
      front: 'north',
      seed: world.seed,
      id: site.id + 0x5000,
    });
    const battle = await insertBattle(client, {
      worldId: world.id,
      waveId: null,
      siteId: site.id,
      villageId: null,
      q: site.q,
      r: site.r,
      attackerStance: data.camps.assault.stance,
      attackerInitial: site.guardians,
      defenderInitial: army.units,
      startedAt: at,
    });
    for (const [i, round] of result.rounds.entries()) {
      const log: RoundLog = {
        round: round.round,
        at: at.toISOString(),
        attackerLosses: round.defenderLosses,
        defenderLosses: round.attackerLosses,
        attackerLeft: round.defenderLeft,
        defenderLeft: round.attackerLeft,
      };
      const last = i === result.rounds.length - 1;
      await recordRound(client, battle.id, log, last ? { status: result.cleared ? 'cleared' : 'repelled', at, loot: null } : null);
    }
    const lost: Record<string, number> = {};
    for (const [unit, n] of Object.entries(army.units)) if (n - (result.armyNow[unit] ?? 0) > 0) lost[unit] = n - (result.armyNow[unit] ?? 0);
    explorers = await armyLosses(client, data, world, army, lost, at);
    await saveGuardians(client, site.id, result.cleared ? {} : result.campNow);
    const kills = total(site.guardians) - total(result.campNow);
    if (hero) {
      await heroAfterBattle(client, data, world, result.cleared ? hero : { ...hero, villageId: army.homeVillageId, armyId: null }, {
        kills,
        won: result.cleared,
        battleId: battle.id,
        at,
      });
    }
    await notifyWorld(client, { worldId: world.id, type: 'battles' });
    if (!result.cleared || total(explorers.units) === 0) {
      await sendHome(client, world, explorers, at, data);
      await tell(client, world, army.ownerAccountId, {
        kind: 'battle_result',
        tier: 'digest',
        title: `Guardians drove your army from the ${data.sites.kinds[site.kind]?.name ?? 'site'}`,
        body: `${kills} of them fell; ${total(result.campNow)} still watch it.`,
      }, at);
      await notifyWorld(client, { worldId: world.id, type: 'world' });
      return;
    }
  }
  // Search the site.
  await saveArmy(client, { ...explorers, status: 'stationed', battleId: null });
  const doneAt = new Date(at.getTime() + (data.sites.kinds[site.kind]!.exploreHours * MS_PER_HOUR) / world.speed);
  const payload: ExplorePayload = { armyId: army.id, siteId: site.id };
  await scheduleEvent(client, world.id, doneAt, 'site_explored', payload);
  await notifyWorld(client, { worldId: world.id, type: 'world' });
}

export const siteHandlers: HandlerRegistry = {
  async site_explored({ client, data, world }, event) {
    const payload = explorePayload.parse(event.payload);
    const army = await loadArmy(client, payload.armyId);
    const site = await loadSite(client, payload.siteId);
    if (army.status !== 'stationed' || army.orders !== 'explore') return;
    if (!site || site.status === 'explored') {
      await sendHome(client, world, army, event.dueAt, data);
      return;
    }
    const leader = await heroWithArmy(client, army.id);
    const ownerHero = leader ?? (army.ownerAccountId !== null ? await loadHero(client, world.id, army.ownerAccountId).catch(() => null) : null);
    const find = rollFind(data, {
      kind: site.kind,
      seed: world.seed,
      siteId: site.id,
      distance: distanceShare(hex(site.q, site.r), world.radius ?? 0),
      foundScrolls: new Set((await listScrolls(client, world.id)).map((s) => s.scroll)),
      ownedGear: new Set(ownerHero ? [...ownerHero.inventory, ...Object.values(ownerHero.gear)] : []),
    });
    let after = army;
    if (find.type === 'resources') after = { ...army, loot: find.resources };
    if (find.type === 'ember') await addEmbers(client, world.id, 1);
    if (find.type === 'gear' && ownerHero) {
      await saveHero(client, { ...ownerHero, inventory: [...ownerHero.inventory, find.item] });
      await notifyWorld(client, { worldId: world.id, type: 'heroes' });
    }
    if (find.type === 'scroll') {
      await addScroll(client, world.id, { scroll: find.scroll, accountId: army.ownerAccountId, siteId: site.id, foundAt: event.dueAt });
      const members = (await listMembers(client, world.id)).map((m) => m.accountId);
      await refreshBonuses(client, data, world, members, event.dueAt);
      await notifyWorld(client, { worldId: world.id, type: 'research' });
    }
    await markExplored(client, site.id, army.ownerAccountId, find, event.dueAt);
    await bridgeQuest(client, data, world, 'site', event.dueAt);
    if (after !== army) await saveArmy(client, after);
    await sendHome(client, world, after, event.dueAt, data);
    const name = data.sites.kinds[site.kind]?.name ?? 'site';
    for (const member of await listMembers(client, world.id)) {
      await tell(client, world, member.accountId, {
        kind: 'site',
        tier: find.type === 'scroll' && member.accountId !== army.ownerAccountId ? 'push' : 'digest',
        title: `The ${name} at (${site.q}, ${site.r}) gave up ${findText(data, find)}`,
        body: find.type === 'scroll' ? data.lore.scrolls[find.scroll]?.description ?? '' : 'Explored and done.',
      }, event.dueAt);
    }
    await notifyWorld(client, { worldId: world.id, type: 'armies' });
    await notifyWorld(client, { worldId: world.id, type: 'world' });
  },
};
