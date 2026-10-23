import { DEFAULT_PREFS, type NotifyPrefs } from '../sim/notifications.js';
import { notifyWorld } from './notify.js';
import type { DbClient } from './pool.js';

export type Tier = 'push' | 'digest';

export interface Notification {
  id: number;
  worldId: number;
  accountId: number;
  kind: string;
  tier: Tier;
  title: string;
  body: string;
  createdAt: Date;
  readAt: Date | null;
  pushedAt: Date | null;
}

interface NotificationRow {
  id: number;
  world_id: number;
  account_id: number;
  kind: string;
  tier: Tier;
  title: string;
  body: string;
  created_at: Date;
  read_at: Date | null;
  pushed_at: Date | null;
}

function fromRow(row: NotificationRow): Notification {
  return {
    id: row.id,
    worldId: row.world_id,
    accountId: row.account_id,
    kind: row.kind,
    tier: row.tier,
    title: row.title,
    body: row.body,
    createdAt: row.created_at,
    readAt: row.read_at,
    pushedAt: row.pushed_at,
  };
}

// Tells a player something happened (push now, or in the next digest).
export async function notifyPlayer(
  client: DbClient,
  n: { worldId: number; accountId: number | null; kind: string; tier: Tier; title: string; body: string; at: Date },
): Promise<void> {
  if (n.accountId === null) return;
  await client.query(
    `INSERT INTO notifications (world_id, account_id, kind, tier, title, body, created_at) VALUES ($1, $2, $3, $4, $5, $6, $7)`,
    [n.worldId, n.accountId, n.kind, n.tier, n.title, n.body, n.at],
  );
  await notifyWorld(client, { worldId: n.worldId, type: 'notifications', accountId: n.accountId });
}

export async function listNotifications(client: DbClient, accountId: number, worldId: number, limit = 40): Promise<Notification[]> {
  const { rows } = await client.query<NotificationRow>(
    `SELECT * FROM notifications WHERE account_id = $1 AND world_id = $2 ORDER BY created_at DESC, id DESC LIMIT $3`,
    [accountId, worldId, limit],
  );
  return rows.map(fromRow);
}

export async function unreadCount(client: DbClient, accountId: number, worldId: number): Promise<number> {
  const { rows } = await client.query<{ n: string }>(
    'SELECT count(*) AS n FROM notifications WHERE account_id = $1 AND world_id = $2 AND read_at IS NULL',
    [accountId, worldId],
  );
  return Number(rows[0]!.n);
}

export async function markAllRead(client: DbClient, accountId: number, worldId: number, at: Date): Promise<void> {
  await client.query('UPDATE notifications SET read_at = $3 WHERE account_id = $1 AND world_id = $2 AND read_at IS NULL', [
    accountId,
    worldId,
    at,
  ]);
}

// Digest-tier notifications not yet summed up by a digest.
export async function undigested(client: DbClient, accountId: number, worldId: number, until: Date): Promise<Notification[]> {
  const { rows } = await client.query<NotificationRow>(
    `SELECT * FROM notifications WHERE account_id = $1 AND world_id = $2 AND tier = 'digest' AND digest_id IS NULL
       AND created_at <= $3 ORDER BY created_at`,
    [accountId, worldId, until],
  );
  return rows.map(fromRow);
}

export async function markDigested(client: DbClient, ids: readonly number[], digestId: number): Promise<void> {
  await client.query('UPDATE notifications SET digest_id = $2 WHERE id = ANY($1)', [ids, digestId]);
}

export async function lastNotificationId(client: DbClient, accountId: number, worldId: number): Promise<number> {
  const { rows } = await client.query<{ id: number }>(
    'SELECT id FROM notifications WHERE account_id = $1 AND world_id = $2 ORDER BY id DESC LIMIT 1',
    [accountId, worldId],
  );
  return rows[0]!.id;
}

// Push notifications still to send, oldest first.
export async function unpushed(client: DbClient, limit = 100): Promise<Notification[]> {
  const { rows } = await client.query<NotificationRow>(
    `SELECT * FROM notifications WHERE tier = 'push' AND pushed_at IS NULL ORDER BY created_at, id LIMIT $1`,
    [limit],
  );
  return rows.map(fromRow);
}

export async function markPushed(client: DbClient, id: number, at: Date): Promise<void> {
  await client.query('UPDATE notifications SET pushed_at = $2 WHERE id = $1', [id, at]);
}

interface PrefsRow {
  quiet_start: number | null;
  quiet_end: number | null;
  utc_offset_minutes: number;
  digest_hour: number;
  push_off: string[];
}

export async function loadPrefs(client: DbClient, accountId: number): Promise<NotifyPrefs> {
  const { rows } = await client.query<PrefsRow>(
    'SELECT quiet_start, quiet_end, utc_offset_minutes, digest_hour, push_off FROM accounts WHERE id = $1',
    [accountId],
  );
  const row = rows[0];
  if (!row) return DEFAULT_PREFS;
  return {
    quietStart: row.quiet_start,
    quietEnd: row.quiet_end,
    utcOffsetMinutes: row.utc_offset_minutes,
    digestHour: row.digest_hour,
    pushOff: row.push_off,
  };
}

export async function savePrefs(client: DbClient, accountId: number, prefs: NotifyPrefs): Promise<void> {
  await client.query(
    'UPDATE accounts SET quiet_start = $2, quiet_end = $3, utc_offset_minutes = $4, digest_hour = $5, push_off = $6 WHERE id = $1',
    [accountId, prefs.quietStart, prefs.quietEnd, prefs.utcOffsetMinutes, prefs.digestHour, prefs.pushOff],
  );
}

export async function registerDevice(client: DbClient, accountId: number, token: string, platform: string): Promise<void> {
  await client.query(
    `INSERT INTO devices (token, account_id, platform) VALUES ($1, $2, $3)
     ON CONFLICT (token) DO UPDATE SET account_id = $2, platform = $3, last_seen_at = now()`,
    [token, accountId, platform],
  );
}

export async function deviceTokens(client: DbClient, accountId: number): Promise<string[]> {
  const { rows } = await client.query<{ token: string }>('SELECT token FROM devices WHERE account_id = $1', [accountId]);
  return rows.map((r) => r.token);
}

export async function forgetDevice(client: DbClient, token: string): Promise<void> {
  await client.query('DELETE FROM devices WHERE token = $1', [token]);
}
