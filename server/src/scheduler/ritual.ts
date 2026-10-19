// Ritual Night and the end of a run (PLAN.md §10): when the last bridge
// stage stands, every active front sends a horde at once; the run is won
// when the last of them is done and the Holy City still stands, and lost
// when its Sanctity reaches 0.
import type { GameData } from '../data/index.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { cancelScheduledWaves, insertWave, lastWave, ritualWavesLeft } from '../db/waves.js';
import { getWorld, listMembers, markRitual, markWon, quietWindow, type World } from '../db/worlds.js';
import { afterQuiet, waveFactor } from '../sim/difficulty.js';
import { planWave, waveFronts } from '../sim/waves.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';
import { tell } from './notices.js';
import { groupPower, waveContext, type WavePayload } from './waves.js';

const MS_PER_HOUR = 3_600_000;

async function tellEveryone(client: DbClient, world: World, title: string, body: string, at: Date): Promise<void> {
  for (const member of await listMembers(client, world.id)) {
    await tell(client, world, member.accountId, { kind: 'ritual', tier: 'push', title, body }, at);
  }
}

// The bridge is whole: the waves still to come are replaced by one horde
// from every active front, setting out together (after quiet hours).
export async function callRitualNight(client: DbClient, data: GameData, world: World, at: Date): Promise<void> {
  const rules = data.bridge.ritualNight;
  const spawnAt = afterQuiet(quietWindow(world), new Date(at.getTime() + (rules.delayHours * MS_PER_HOUR) / world.speed));
  await cancelScheduledWaves(client, world.id);
  await markRitual(client, world.id, spawnAt);
  const ctx = await waveContext(client, world);
  const fronts = waveFronts(data, world.activeFronts);
  const first = ((await lastWave(client, world.id))?.index ?? -1) + 1;
  // Consecutive indexes take every front once (planWave picks index % fronts).
  for (let i = 0; i < fronts.length; i++) {
    const index = first + i;
    const sizeFactor = waveFactor(data, world.difficulty, await groupPower(client, data, world, index)) * rules.sizeFactor;
    const wave = await insertWave(client, world.id, { ...planWave(data, { ...ctx, sizeFactor }, index, null), spawnAt }, true);
    const payload: WavePayload = { waveId: wave.id };
    await scheduleEvent(client, world.id, spawnAt, 'wave_spawn', payload);
  }
  await scheduleEvent(client, world.id, new Date(spawnAt.getTime() + (rules.checkHours * MS_PER_HOUR) / world.speed), 'ritual_check', {});
  await tellEveryone(client, world, 'Ritual Night', rules.story, at);
  await notifyWorld(client, { worldId: world.id, type: 'waves' });
  await notifyWorld(client, { worldId: world.id, type: 'world' });
}

export async function runLost(client: DbClient, data: GameData, world: World, at: Date): Promise<void> {
  const { title, story } = data.bridge.endings.lost;
  await tellEveryone(client, world, title, story, at);
  await notifyWorld(client, { worldId: world.id, type: 'world' });
}

export const ritualHandlers: HandlerRegistry = {
  // Until Ritual Night's last horde is done; then, if the city stands, the run is won.
  async ritual_check({ client, data }, event) {
    const world = await getWorld(client, event.worldId);
    if (world.status !== 'running') return;
    if ((await ritualWavesLeft(client, world.id)) > 0) {
      const next = new Date(event.dueAt.getTime() + (data.bridge.ritualNight.checkHours * MS_PER_HOUR) / world.speed);
      await scheduleEvent(client, world.id, next, 'ritual_check', {});
      return;
    }
    await markWon(client, world.id, event.dueAt);
    const { title, story } = data.bridge.endings.won;
    await tellEveryone(client, world, title, story, event.dueAt);
    await notifyWorld(client, { worldId: world.id, type: 'world' });
  },
};
