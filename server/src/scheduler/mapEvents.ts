// Daily map events on the scheduler (data/events.json, sim/events.ts):
// map_event raises the day's event and plans the next day's; map_event_end
// takes it away again when its time is up, unless an army is on its way.
import { z } from 'zod';
import type { GameData } from '../data/index.js';
import { armiesHolding } from '../db/armies.js';
import { deleteCamp, loadCamp } from '../db/camps.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { deleteSite, insertHardSite, listSites, loadSite } from '../db/sites.js';
import { listVillages } from '../db/villages.js';
import { listMembers, loadHexes, type World } from '../db/worlds.js';
import { planMapEvent } from '../sim/events.js';
import { hex } from '../sim/hex.js';
import { createCamp } from './camps.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';
import { takenHexes } from './horde.js';
import { tell } from './notices.js';

const MS_PER_HOUR = 3_600_000;
const mapEventPayload = z.object({ day: z.number().int().positive() });
const mapEventEndPayload = z.object({ campId: z.number().int().optional(), siteId: z.number().int().optional() });

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
    }
    if (plan) {
      for (const member of await listMembers(client, world.id)) {
        await tell(client, world, member.accountId, plan.kind === 'captives'
          ? { kind: 'site', tier: 'digest', title: 'Captives are held at ({q}, {r})', body: 'Clear the camp to free them, before they are taken away.', vars: { q: plan.cell.q, r: plan.cell.r } }
          : { kind: 'site', tier: 'digest', title: 'A forbidding ruin rises at ({q}, {r})', body: 'Strong guardians watch it, and rich finds lie within, for a while.', vars: { q: plan.cell.q, r: plan.cell.r } }, at);
      }
      await notifyWorld(client, { worldId: world.id, type: 'world' });
    }
    await scheduleEvent(client, world.id, new Date(at.getTime() + hoursMs(data.events.everyHours, world.speed)), 'map_event', { day: day + 1 });
  },

  // Its time is up: gone, unless an army is already on its way to it.
  async map_event_end({ client, world }, event) {
    const { campId, siteId } = mapEventEndPayload.parse(event.payload);
    if (campId !== undefined) {
      const camp = await loadCamp(client, campId);
      if (!camp || camp.status !== 'active') return;
      if ((await armiesHolding(client, world.id, camp.q, camp.r, ['marching', 'engaged'])).some((a) => a.orders === 'clear')) return;
      await deleteCamp(client, camp.id);
    }
    if (siteId !== undefined) {
      const site = await loadSite(client, siteId);
      if (!site || site.status !== 'unexplored') return;
      if ((await armiesHolding(client, world.id, site.q, site.r, ['marching', 'engaged', 'stationed'])).some((a) => a.orders === 'explore')) return;
      await deleteSite(client, site.id);
    }
    await notifyWorld(client, { worldId: world.id, type: 'world' });
  },
};
