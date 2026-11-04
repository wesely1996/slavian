// Scout missions on the scheduler: scout_arrive resolves who survives and
// writes the shared report; scout_return brings the survivors home.
import { z } from 'zod';
import { notifyWorld } from '../db/notify.js';
import { effectiveBonuses } from '../db/heroes.js';
import { loadMission, markMissionDone, recordReport } from '../db/scouting.js';
import { loadVillage, saveVillageState } from '../db/villages.js';
import { loadWave } from '../db/waves.js';
import { SCOUT_UNIT, assassinates, intelOf, scoutReport, survivingScouts } from '../sim/scouting.js';
import { slayLeader } from './leaders.js';
import { loseAway, returnHome } from '../sim/village.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';
import { finishRuinSearch, loadRuinSearch } from '../db/ruinSearches.js';
import { insertSites, listSites, siteAt } from '../db/sites.js';
import { loadHexes } from '../db/worlds.js';
import { hex } from '../sim/hex.js';
import { searchRuin } from '../sim/sites.js';
import { takenHexes } from './horde.js';
import { tell } from './notices.js';

export const missionPayload = z.object({ missionId: z.number().int() });
export const ruinSearchPayload = z.object({ searchId: z.number().int() });
export type RuinSearchPayload = z.infer<typeof ruinSearchPayload>;
export type MissionPayload = z.infer<typeof missionPayload>;

export const scoutingHandlers: HandlerRegistry = {
  // Scouts back from searching for ruins: with a new site, or nothing.
  async ruin_search({ client, data, world }, event) {
    const search = await loadRuinSearch(client, ruinSearchPayload.parse(event.payload).searchId);
    if (search.status !== 'out') return;
    const village = await loadVillage(client, search.villageId).catch(() => null);
    let siteId: number | null = null;
    if (village && world.radius !== null) {
      const terrain = new Map((await loadHexes(client, world.id)).map(([q, r, t]) => [`${q},${r}`, t] as const));
      const sites = await listSites(client, world.id);
      const placed = searchRuin(data, {
        terrain,
        radius: world.radius,
        center: hex(village.q, village.r),
        taken: await takenHexes(client, world.id),
        sites: sites.map((s) => hex(s.q, s.r)),
        scouts: search.scouts,
        seed: (world.seed ^ Math.imul(search.id, 0x2c1b3c6d)) >>> 0,
      });
      if (placed) {
        await insertSites(client, world.id, [placed]);
        siteId = (await siteAt(client, world.id, placed.q, placed.r))?.id ?? null;
      }
      await saveVillageState(client, village.id, returnHome(data, village.state, SCOUT_UNIT, search.scouts, event.dueAt, world.speed));
      await tell(client, world, village.ownerAccountId, placed
        ? {
            kind: 'site',
            tier: 'digest',
            title: 'Scouts from {village} found a forgotten ruin',
            body: 'A {site} lies at ({q}, {r}). Send an army to explore it.',
            vars: { village: village.name, site: data.sites.kinds[placed.kind]?.name ?? placed.kind, q: placed.q, r: placed.r },
          }
        : {
            kind: 'site',
            tier: 'digest',
            title: 'Scouts from {village} found no ruins',
            body: 'They searched the land around it and came back empty-handed.',
            vars: { village: village.name },
          }, event.dueAt);
      await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
    }
    await finishRuinSearch(client, search.id, siteId);
    await notifyWorld(client, { worldId: world.id, type: 'world' });
  },

  async scout_arrive({ client, data, world }, event) {
    const mission = await loadMission(client, missionPayload.parse(event.payload).missionId);
    if (mission.status !== 'outbound') return;
    const wave = await loadWave(client, mission.waveId);
    // A horde that already scattered can't hurt anyone.
    const dispersed = wave.status === 'dispersed' || wave.status === 'defeated';
    const village = await loadVillage(client, mission.villageId);
    const came = dispersed
      ? mission.units
      : survivingScouts(data, wave.front, mission.units, world.seed, mission.id, await effectiveBonuses(client, data, village));
    const survivors = Object.values(came).reduce((sum, n) => sum + n, 0);
    // Assassins who reach a horde led by a leader may kill them.
    const slain = !dispersed && wave.leaderId !== null && assassinates(data, came, world.seed, mission.id)
      ? await slayLeader(client, data, world, wave, village.name, event.dueAt)
      : null;
    const report = scoutReport(data, {
      front: wave.front,
      composition: wave.composition,
      stance: wave.stance,
      sent: mission.sent,
      survivors,
      intel: intelOf(data, came),
      dispersed,
      seed: world.seed,
      missionId: mission.id,
    });
    await recordReport(client, mission.id, slain ? { ...report, leaderSlain: slain } : report, came);

    let state = village.state;
    for (const [unit, n] of Object.entries(mission.units)) {
      const lost = n - (came[unit] ?? 0);
      if (lost > 0) state = loseAway(data, state, unit, lost, event.dueAt, world.speed);
    }
    if (state !== village.state) {
      await saveVillageState(client, village.id, state);
      await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
    }
    const payload: MissionPayload = { missionId: mission.id };
    await scheduleEvent(client, world.id, mission.returnsAt, 'scout_return', payload);
    await notifyWorld(client, { worldId: world.id, type: 'scouting' });
  },

  async scout_return({ client, data, world }, event) {
    const mission = await loadMission(client, missionPayload.parse(event.payload).missionId);
    if (mission.status !== 'returning') return;
    const village = await loadVillage(client, mission.villageId);
    let state = village.state;
    for (const [unit, n] of Object.entries(mission.survivorUnits ?? {})) if (n > 0) state = returnHome(data, state, unit, n, event.dueAt, world.speed);
    await saveVillageState(client, village.id, state);
    await markMissionDone(client, mission.id);
    await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
    await notifyWorld(client, { worldId: world.id, type: 'scouting' });
  },
};
