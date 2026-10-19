// What players are told, and when: game events become notifications (push
// or digest); daily_digest sums up the rest once a day; wave_warning warns
// of a horde a few hours out.
import { z } from 'zod';
import type { GameData } from '../data/index.js';
import {
  lastNotificationId,
  loadPrefs,
  markDigested,
  notifyPlayer,
  undigested,
  type Tier,
} from '../db/notifications.js';
import type { DbClient } from '../db/pool.js';
import { loadVillage } from '../db/villages.js';
import { loadWave } from '../db/waves.js';
import { listMembers, type World } from '../db/worlds.js';
import { digestSummary, nextDigestAt } from '../sim/notifications.js';
import { warningHours } from '../sim/walls.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';

const MS_PER_HOUR = 3_600_000;

export async function tell(
  client: DbClient,
  world: World,
  accountId: number | null,
  notice: { kind: string; tier: Tier; title: string; body: string },
  at: Date,
): Promise<void> {
  await notifyPlayer(client, { worldId: world.id, accountId, ...notice, at });
}

// Tells the owner of a village.
export async function tellOwner(
  client: DbClient,
  world: World,
  villageId: number,
  notice: (villageName: string) => { kind: string; tier: Tier; title: string; body: string },
  at: Date,
): Promise<void> {
  const village = await loadVillage(client, villageId);
  await tell(client, world, village.ownerAccountId, notice(village.name), at);
}

export const wavePayload = z.object({ waveId: z.number().int() });
export const digestPayload = z.object({ accountId: z.number().int() });

// A horde has set out for a village: warn its owner a few hours before it
// arrives (at once if it is already that close).
export async function planWaveWarning(client: DbClient, data: GameData, world: World, waveId: number, at: Date): Promise<void> {
  const wave = await loadWave(client, waveId);
  if (wave.targetVillageId === null || !wave.arrivesAt) return;
  // A watchtower sees the horde coming sooner.
  const target = await loadVillage(client, wave.targetVillageId);
  const hours = data.notifications.waveWarningHours + warningHours(data, target.state.plots);
  const warnAt = new Date(wave.arrivesAt.getTime() - (hours * MS_PER_HOUR) / world.speed);
  await scheduleEvent(client, world.id, warnAt > at ? warnAt : at, 'wave_warning', { waveId });
}

// Every member gets a daily digest at their digest hour.
export async function ensureDigests(client: DbClient, world: World, from: Date): Promise<void> {
  for (const member of await listMembers(client, world.id)) {
    const { rows } = await client.query(
      `SELECT 1 FROM scheduled_events WHERE world_id = $1 AND type = 'daily_digest' AND status = 'pending' AND payload @> $2::jsonb`,
      [world.id, JSON.stringify({ accountId: member.accountId })],
    );
    if (rows.length) continue;
    const prefs = await loadPrefs(client, member.accountId);
    await scheduleEvent(client, world.id, nextDigestAt(from, prefs), 'daily_digest', { accountId: member.accountId });
  }
}

export const noticeHandlers: HandlerRegistry = {
  async wave_warning({ client, world }, event) {
    const wave = await loadWave(client, wavePayload.parse(event.payload).waveId);
    if (wave.status !== 'marching' || wave.targetVillageId === null || !wave.arrivesAt) return;
    const hours = Math.max(0, (wave.arrivesAt.getTime() - event.dueAt.getTime()) / MS_PER_HOUR);
    const when = hours >= 1 ? `in about ${Math.round(hours)} hour${Math.round(hours) === 1 ? '' : 's'}` : 'within the hour';
    await tellOwner(client, world, wave.targetVillageId, (name) => ({
      kind: 'wave_soon',
      tier: 'push',
      title: `A horde is coming to ${name}`,
      body: `The ${wave.threat.toLowerCase()} ${wave.front} horde arrives ${when}. Check the garrison and its stance.`,
    }), event.dueAt);
  },

  async daily_digest({ client, world }, event) {
    const { accountId } = digestPayload.parse(event.payload);
    const pending = await undigested(client, accountId, world.id, event.dueAt);
    if (pending.length) {
      await tell(client, world, accountId, {
        kind: 'digest',
        tier: 'push',
        title: `Today in ${world.name}`,
        body: digestSummary(pending.map((n) => n.kind)),
      }, event.dueAt);
      const digestId = await lastNotificationId(client, accountId, world.id);
      await markDigested(client, pending.map((n) => n.id), digestId);
    }
    const prefs = await loadPrefs(client, accountId);
    await scheduleEvent(client, world.id, nextDigestAt(event.dueAt, prefs), 'daily_digest', { accountId });
  },
};
