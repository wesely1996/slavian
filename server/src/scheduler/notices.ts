// What players are told, and when: game events become notifications (push
// or digest); daily_digest sums up the rest once a day; wave_warning warns
// of a horde a few hours out. A notice carries English templates plus the
// values to fill in, and is rendered in the recipient's language (i18n.ts).
import { z } from 'zod';
import type { GameData } from '../data/index.js';
import { accountLanguage } from '../db/accounts.js';
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
import { localize } from '../i18n.js';
import { digestSummary, nextDigestAt } from '../sim/notifications.js';
import { warningHours } from '../sim/walls.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';

const MS_PER_HOUR = 3_600_000;

// A notice before rendering: English templates with {placeholder} values.
export interface Notice {
  kind: string;
  tier: Tier;
  title: string;
  body: string;
  vars?: Record<string, string | number>;
  // A body written for the reader's language instead of `body` (the digest).
  bodyFor?: (language: string) => string;
}

export async function tell(
  client: DbClient,
  world: World,
  accountId: number | null,
  notice: Notice,
  at: Date,
): Promise<void> {
  const language = accountId === null ? 'en' : await accountLanguage(client, accountId);
  await notifyPlayer(client, {
    worldId: world.id,
    accountId,
    kind: notice.kind,
    tier: notice.tier,
    title: localize(language, notice.title, notice.vars),
    body: notice.bodyFor ? notice.bodyFor(language) : localize(language, notice.body, notice.vars),
    at,
  });
}

// Tells the owner of a village.
export async function tellOwner(
  client: DbClient,
  world: World,
  villageId: number,
  notice: (villageName: string) => Notice,
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
    const hours = Math.round(Math.max(0, (wave.arrivesAt.getTime() - event.dueAt.getTime()) / MS_PER_HOUR));
    const when = hours > 1 ? 'in about {hours} hours' : hours === 1 ? 'in about an hour' : 'within the hour';
    await tellOwner(client, world, wave.targetVillageId, (name) => ({
      kind: 'wave_soon',
      tier: 'push',
      title: 'A horde is coming to {village}',
      body: `The {threat} {front} horde arrives ${when}. Check the garrison and its stance.`,
      vars: { village: name, threat: wave.threat.toLowerCase(), front: wave.front, hours },
    }), event.dueAt);
  },

  async daily_digest({ client, world }, event) {
    const { accountId } = digestPayload.parse(event.payload);
    const pending = await undigested(client, accountId, world.id, event.dueAt);
    if (pending.length) {
      await tell(client, world, accountId, {
        kind: 'digest',
        tier: 'push',
        title: 'Today in {world}',
        body: digestSummary(pending.map((n) => n.kind)),
        bodyFor: (language) => digestSummary(pending.map((n) => n.kind), language),
        vars: { world: world.name },
      }, event.dueAt);
      const digestId = await lastNotificationId(client, accountId, world.id);
      await markDigested(client, pending.map((n) => n.id), digestId);
    }
    const prefs = await loadPrefs(client, accountId);
    await scheduleEvent(client, world.id, nextDigestAt(event.dueAt, prefs), 'daily_digest', { accountId });
  },
};
