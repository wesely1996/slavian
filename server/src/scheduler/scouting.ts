// Scout missions on the scheduler: scout_arrive resolves who survives and
// writes the shared report; scout_return brings the survivors home.
import { z } from 'zod';
import { notifyWorld } from '../db/notify.js';
import { loadMission, markMissionDone, recordReport } from '../db/scouting.js';
import { loadVillage, saveVillageState } from '../db/villages.js';
import { loadWave } from '../db/waves.js';
import { SCOUT_UNIT, scoutReport, survivorsOf } from '../sim/scouting.js';
import { loseAway, returnHome } from '../sim/village.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';

export const missionPayload = z.object({ missionId: z.number().int() });
export type MissionPayload = z.infer<typeof missionPayload>;

export const scoutingHandlers: HandlerRegistry = {
  async scout_arrive({ client, data, world }, event) {
    const mission = await loadMission(client, missionPayload.parse(event.payload).missionId);
    if (mission.status !== 'outbound') return;
    const wave = await loadWave(client, mission.waveId);
    // A horde that already scattered can't hurt anyone.
    const dispersed = wave.status === 'dispersed' || wave.status === 'defeated';
    const survivors = dispersed ? mission.sent : survivorsOf(data, wave.front, mission.sent, world.seed, mission.id);
    const report = scoutReport(data, {
      front: wave.front,
      composition: wave.composition,
      stance: wave.stance,
      sent: mission.sent,
      survivors,
      dispersed,
      seed: world.seed,
      missionId: mission.id,
    });
    await recordReport(client, mission.id, report);

    const village = await loadVillage(client, mission.villageId);
    const lost = mission.sent - survivors;
    if (lost > 0) {
      await saveVillageState(client, village.id, loseAway(data, village.state, SCOUT_UNIT, lost, event.dueAt, world.speed));
      await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
    }
    const payload: MissionPayload = { missionId: mission.id };
    await scheduleEvent(client, world.id, mission.returnsAt, 'scout_return', payload);
    await notifyWorld(client, { worldId: world.id, type: 'scouting' });
  },

  async scout_return({ client, world }, event) {
    const mission = await loadMission(client, missionPayload.parse(event.payload).missionId);
    if (mission.status !== 'returning') return;
    const village = await loadVillage(client, mission.villageId);
    await saveVillageState(client, village.id, returnHome(village.state, SCOUT_UNIT, mission.survivors ?? 0));
    await markMissionDone(client, mission.id);
    await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
    await notifyWorld(client, { worldId: world.id, type: 'scouting' });
  },
};
