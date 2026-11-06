// Daily map events on the scheduler (data/events.json, sim/events.ts):
// map_event raises the day's event and plans the next day's; map_event_end
// takes it away again when its time is up, unless an army is on its way (or,
// for a shipyard, someone has sent resources), and the horde hates the more
// for it (scheduler/eventOutcomes.ts). A paid-for shipyard builds
// its boat (shipyard_done), struck by raiders (shipyard_raid) on the way.
import { z } from 'zod';
import { combatants, withIntel } from '../sim/scouting.js';
import type { GameData } from '../data/index.js';
import { armiesHolding, saveArmy } from '../db/armies.js';
import { deleteCamp, loadCamp } from '../db/camps.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { listRiverEdges } from '../db/rivers.js';
import { deleteShipyard, insertShipyard, listShipyards, loadShipyard, saveShipyard, type Shipyard } from '../db/shipyards.js';
import { deleteSite, insertHardSite, listSites, loadSite } from '../db/sites.js';
import { listVillages, loadVillage, saveVillageState } from '../db/villages.js';
import { RuleError } from '../errors.js';
import { playerStats, total } from '../sim/battle.js';
import { repelRaid } from '../sim/camps.js';
import { listMembers, loadHexes, type World } from '../db/worlds.js';
import { eventFront, planMapEvent } from '../sim/events.js';
import { hex, hexDistance } from '../sim/hex.js';
import type { Front } from '../sim/mapgen.js';
import { amountsAt, mapResources, RESOURCE_KINDS, spend, type Resources } from '../sim/resources.js';
import { armyLosses, sendHome } from './armies.js';
import { createCamp } from './camps.js';
import { bountyTotal, failEvent, rewardEvent } from './eventOutcomes.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';
import { takenHexes } from './horde.js';
import { tell } from './notices.js';

const MS_PER_HOUR = 3_600_000;
const mapEventPayload = z.object({ day: z.number().int().positive() });
const mapEventEndPayload = z.object({ campId: z.number().int().optional(), siteId: z.number().int().optional(), shipyardId: z.number().int().optional() });
const shipyardPayload = z.object({ shipyardId: z.number().int() });

function hoursMs(hours: number, worldSpeed: number): number {
  return Math.round((hours * MS_PER_HOUR) / worldSpeed);
}

// A running world has its next day's event planned (a new run: the first
// a game day in; one from before daily events: the next day to come).
export async function ensureMapEvents(client: DbClient, data: GameData, world: World, now: Date): Promise<void> {
  if (world.status !== 'running' || !world.startedAt) return;
  const { rows } = await client.query("SELECT 1 FROM scheduled_events WHERE world_id = $1 AND type = 'map_event' AND status = 'pending'", [world.id]);
  if (rows.length) return;
  const every = hoursMs(data.events.everyHours, world.speed);
  const day = Math.max(1, Math.floor((now.getTime() - world.startedAt.getTime()) / every) + 1);
  await scheduleEvent(client, world.id, new Date(world.startedAt.getTime() + day * every), 'map_event', { day });
}

export const mapEventHandlers: HandlerRegistry = {
  async map_event({ client, data, world }, event) {
    const { day } = mapEventPayload.parse(event.payload);
    if (world.status !== 'running') return;
    const at = event.dueAt;
    const villages = (await listVillages(client, world.id)).filter((v) => !v.ruin && v.ownerAccountId !== null);
    const plan = planMapEvent(data, {
      terrain: new Map((await loadHexes(client, world.id)).map(([q, r, t]) => [`${q},${r}`, t] as const)),
      radius: world.radius ?? 0,
      villages: villages.map((v) => hex(v.q, v.r)),
      taken: await takenHexes(client, world.id),
      sites: (await listSites(client, world.id)).map((s) => hex(s.q, s.r)),
      rivers: await listRiverEdges(client, world.id),
      shipyards: (await listShipyards(client, world.id)).map((s) => hex(s.q, s.r)),
      activeFronts: world.activeFronts,
      seed: world.seed,
      day,
      players: (await listMembers(client, world.id)).length,
    });
    const endsAt = new Date(at.getTime() + hoursMs(data.events.lastsHours, world.speed));
    if (plan?.kind === 'captives') {
      const camp = await createCamp(client, data, world, { kind: 'captives', front: plan.front, q: plan.cell.q, r: plan.cell.r, units: plan.guards, waveId: null, reward: plan.reward, endsAt }, at);
      await scheduleEvent(client, world.id, endsAt, 'map_event_end', { campId: camp.id });
    } else if (plan?.kind === 'ruin') {
      const siteId = await insertHardSite(client, world.id, plan.site, endsAt);
      await scheduleEvent(client, world.id, endsAt, 'map_event_end', { siteId });
    } else if (plan?.kind === 'shipyard') {
      const shipyardId = await insertShipyard(client, world.id, { cell: plan.cell, edge: plan.edge, cost: data.events.kinds.shipyard.cost, front: plan.front, raiders: plan.raiders, endsAt });
      await scheduleEvent(client, world.id, endsAt, 'map_event_end', { shipyardId });
    }
    if (plan) {
      const vars = { q: plan.cell.q, r: plan.cell.r, front: eventFront(plan.cell, world.activeFronts), bounty: bountyTotal(data, world, at) };
      await tellAll(client, world, plan.kind === 'captives'
        ? { kind: 'event', tier: 'push', title: 'Captives are held at ({q}, {r})', body: 'Clear the camp to free them before they are taken away, for a bounty of at least {bounty} resources. If they are taken, the next horde from the {front} hates you the more.', vars }
        : plan.kind === 'ruin'
          ? { kind: 'event', tier: 'push', title: 'A forbidding ruin rises at ({q}, {r})', body: 'Strong guardians watch it, and rich finds lie within, for a while. Searching it brings a bounty of at least {bounty} resources; left alone, it rouses the next horde from the {front}.', vars }
          : { kind: 'event', tier: 'push', title: 'Boatwrights wait at ({q}, {r})', body: 'Send them resources from your villages, and they build a boat that carries armies and caravans fast along the river, with a bounty of at least {bounty} resources for everyone. If nobody does, the next horde from the {front} hates you the more.', vars }, at);
      await notifyWorld(client, { worldId: world.id, type: 'world' });
    }
    await scheduleEvent(client, world.id, new Date(at.getTime() + hoursMs(data.events.everyHours, world.speed)), 'map_event', { day: day + 1 });
  },

  // Its time is up: gone, unless an army is already on its way to it.
  async map_event_end({ client, data, world }, event) {
    const { campId, siteId, shipyardId } = mapEventEndPayload.parse(event.payload);
    if (campId !== undefined) {
      const camp = await loadCamp(client, campId);
      if (!camp || camp.status !== 'active') return;
      if ((await armiesHolding(client, world.id, camp.q, camp.r, ['marching', 'engaged'])).some((a) => a.orders === 'clear')) return;
      await deleteCamp(client, camp.id);
      await failEvent(client, data, world, camp.front as Front, 'The captives at ({q}, {r}) were taken away', { q: camp.q, r: camp.r }, event.dueAt);
    }
    if (siteId !== undefined) {
      const site = await loadSite(client, siteId);
      if (!site || site.status !== 'unexplored') return;
      if ((await armiesHolding(client, world.id, site.q, site.r, ['marching', 'engaged', 'stationed'])).some((a) => a.orders === 'explore')) return;
      await deleteSite(client, site.id);
      await failEvent(client, data, world, eventFront(hex(site.q, site.r), world.activeFronts), 'The forbidding ruin at ({q}, {r}) sank back into the earth', { q: site.q, r: site.r }, event.dueAt);
    }
    if (shipyardId !== undefined) {
      const shipyard = await loadShipyard(client, shipyardId);
      // Gone only if nobody has sent anything, nor has a caravan on its way.
      if (!shipyard || shipyard.status !== 'open' || total(shipyard.paid) > 0) return;
      const { rows: coming } = await client.query("SELECT 1 FROM caravans WHERE destination_shipyard_id = $1 AND status = 'outbound'", [shipyard.id]);
      if (coming.length) return;
      await deleteShipyard(client, shipyard.id);
      await failEvent(client, data, world, shipyard.front as Front, 'The boatwrights at ({q}, {r}) gave up and left', { q: shipyard.q, r: shipyard.r }, event.dueAt);
    }
    await notifyWorld(client, { worldId: world.id, type: 'world' });
  },

  // Raiders strike the shipyard: the armies standing on it fight them one
  // after another; if none drives them off, work is lost.
  async shipyard_raid({ client, data, world }, event) {
    const shipyard = await loadShipyard(client, shipyardPayload.parse(event.payload).shipyardId);
    if (!shipyard || shipyard.status !== 'building' || shipyard.nextRaidAt?.getTime() !== event.dueAt.getTime()) return;
    const rules = data.events.kinds.shipyard;
    const at = event.dueAt;
    let raiders: Record<string, number> = { ...shipyard.raiders };
    const where = { q: shipyard.q, r: shipyard.r };
    for (const [i, army] of (await armiesHolding(client, world.id, shipyard.q, shipyard.r, ['stationed'])).entries()) {
      if (total(raiders) === 0) break;
      // Scouts alone stand aside.
      if (total(combatants(data, army.units)) === 0) continue;
      const home = await loadVillage(client, army.homeVillageId);
      const result = repelRaid(data, {
        army: combatants(data, army.units),
        armyStats: withIntel(data, army.units, playerStats(data, home.state.bonuses, false)),
        armyStance: army.stance,
        raiders,
        raiderStance: rules.raiderStance,
        front: shipyard.front as Front,
        seed: world.seed,
        id: shipyard.id * 64 + shipyard.raids * 8 + i,
      });
      const lost: Record<string, number> = {};
      for (const [unit, n] of Object.entries(combatants(data, army.units))) if (n - (result.armyNow[unit] ?? 0) > 0) lost[unit] = n - (result.armyNow[unit] ?? 0);
      const after = await armyLosses(client, data, world, army, lost, at);
      const kills = total(raiders) - total(result.raidersNow);
      raiders = result.held ? {} : result.raidersNow;
      if (result.held && total(after.units) > 0) await saveArmy(client, after);
      else await sendHome(client, world, after, at, data);
      await tell(client, world, army.ownerAccountId, {
        kind: 'battle_result',
        tier: 'digest',
        title: result.held ? 'Your army drove the raiders off the shipyard at ({q}, {r})' : 'Raiders broke your army at the shipyard at ({q}, {r})',
        body: '{kills} of them fell, for {lost} of yours.',
        vars: { ...where, kills, lost: total(lost) },
      }, at);
    }
    const held = total(raiders) === 0;
    const completesAt = held ? shipyard.completesAt! : new Date(shipyard.completesAt!.getTime() + hoursMs(rules.setbackHours, world.speed));
    const next = new Date(at.getTime() + hoursMs(rules.raidEveryHours, world.speed));
    const after: Shipyard = { ...shipyard, raids: shipyard.raids + 1, completesAt, nextRaidAt: next < completesAt ? next : null };
    await saveShipyard(client, after);
    if (!held) {
      await scheduleEvent(client, world.id, completesAt, 'shipyard_done', { shipyardId: shipyard.id });
      await tellAll(client, world, { kind: 'site', tier: 'push', title: 'Raiders burned work at the shipyard at ({q}, {r})', body: 'The boat is set back {hours} hours. Armies standing there fight the next raiders.', vars: { ...where, hours: rules.setbackHours } }, at);
    }
    if (after.nextRaidAt) await scheduleEvent(client, world.id, after.nextRaidAt, 'shipyard_raid', { shipyardId: shipyard.id });
    await notifyWorld(client, { worldId: world.id, type: 'armies' });
    await notifyWorld(client, { worldId: world.id, type: 'world' });
  },

  // The boat is done: from now on its river is a fast lane.
  // Every member gets the bounty.
  async shipyard_done({ client, data, world }, event) {
    const shipyard = await loadShipyard(client, shipyardPayload.parse(event.payload).shipyardId);
    if (!shipyard || shipyard.status !== 'building' || shipyard.completesAt?.getTime() !== event.dueAt.getTime()) return;
    await saveShipyard(client, { ...shipyard, status: 'done', nextRaidAt: null });
    for (const member of await listMembers(client, world.id)) {
      await rewardEvent(client, data, world, member.accountId, {
        title: 'The boat at ({q}, {r}) is ready',
        body: "Armies, caravans and scouts move fast between hexes along its river. The boatwrights' bounty for {village}: {wood} wood, {stone} stone, {grain} grain and {iron} iron.",
        vars: { q: shipyard.q, r: shipyard.r },
      }, event.dueAt);
    }
    await notifyWorld(client, { worldId: world.id, type: 'world' });
  },
};

async function tellAll(client: DbClient, world: World, notice: Parameters<typeof tell>[3], at: Date): Promise<void> {
  for (const member of await listMembers(client, world.id)) await tell(client, world, member.accountId, notice, at);
}

// A village sends what the shipyard still needs (as much as it has); once
// it is all paid, the boat is begun, and raiders come.
export async function payShipyard(client: DbClient, data: GameData, world: World, villageId: number, shipyardId: number, at: Date): Promise<Shipyard> {
  const rules = data.events.kinds.shipyard;
  const shipyard = await loadShipyard(client, shipyardId);
  if (!shipyard || shipyard.worldId !== world.id) throw new RuleError('No such shipyard in this world');
  if (shipyard.status !== 'open') throw new RuleError('The boat is already paid for');
  const village = await loadVillage(client, villageId);
  if (hexDistance(hex(village.q, village.r), hex(shipyard.q, shipyard.r)) > rules.range) throw new RuleError(`Villages within ${rules.range} hexes send to a shipyard`);
  const have = amountsAt(village.state.ledger, at);
  const sent: Resources = mapResources((k) => Math.max(0, Math.min(shipyard.cost[k] - shipyard.paid[k], Math.floor(have[k]))));
  if (total(sent) === 0) throw new RuleError('The village has nothing the shipyard needs');
  await saveVillageState(client, village.id, { ...village.state, ledger: spend(village.state.ledger, at, sent) });
  const after = await payIntoShipyard(client, data, world, shipyard, sent, at);
  await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
  return after;
}

// Resources reach an open shipyard (from a village nearby, or by caravan):
// once it is all paid, the boat is begun, and raiders come.
export async function payIntoShipyard(client: DbClient, data: GameData, world: World, shipyard: Shipyard, sent: Resources, at: Date): Promise<Shipyard> {
  const rules = data.events.kinds.shipyard;
  const paid = mapResources((k) => shipyard.paid[k] + sent[k]);
  let after: Shipyard = { ...shipyard, paid };
  if (RESOURCE_KINDS.every((k) => paid[k] >= shipyard.cost[k])) {
    const completesAt = new Date(at.getTime() + hoursMs(rules.buildHours, world.speed));
    const raid = new Date(at.getTime() + hoursMs(rules.raidEveryHours, world.speed));
    after = { ...after, status: 'building', completesAt, nextRaidAt: raid < completesAt ? raid : null };
    await scheduleEvent(client, world.id, completesAt, 'shipyard_done', { shipyardId: shipyard.id });
    if (after.nextRaidAt) await scheduleEvent(client, world.id, after.nextRaidAt, 'shipyard_raid', { shipyardId: shipyard.id });
    await tellAll(client, world, { kind: 'site', tier: 'push', title: 'The boat at ({q}, {r}) is begun', body: 'Raiders will come every {every} hours until it is done; armies standing there fight them.', vars: { q: shipyard.q, r: shipyard.r, every: rules.raidEveryHours } }, at);
  }
  await saveShipyard(client, after);
  await notifyWorld(client, { worldId: world.id, type: 'world' });
  return after;
}
