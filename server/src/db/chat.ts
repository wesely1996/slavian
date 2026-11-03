// The group chat of a world: one channel, for its members (api/app.ts).
import type { DbClient } from './pool.js';

export interface ChatMessage {
  id: number;
  accountId: number;
  name: string;
  body: string;
  at: string;
}

interface ChatRow {
  id: string | number;
  account_id: string | number;
  name: string;
  body: string;
  created_at: Date;
}

function fromRow(row: ChatRow): ChatMessage {
  return {
    id: Number(row.id),
    accountId: Number(row.account_id),
    name: row.name,
    body: row.body,
    at: row.created_at.toISOString(),
  };
}

export async function insertChatMessage(
  client: DbClient,
  message: { worldId: number; accountId: number; name: string; body: string; at: Date },
): Promise<ChatMessage> {
  const { rows } = await client.query<ChatRow>(
    'INSERT INTO chat_messages (world_id, account_id, name, body, created_at) VALUES ($1, $2, $3, $4, $5) RETURNING *',
    [message.worldId, message.accountId, message.name, message.body, message.at],
  );
  return fromRow(rows[0]!);
}

// The latest `limit` messages before `before` (an id; none: the newest),
// oldest first.
export async function listChatMessages(client: DbClient, worldId: number, limit: number, before: number | null): Promise<ChatMessage[]> {
  const { rows } = await client.query<ChatRow>(
    `SELECT * FROM chat_messages WHERE world_id = $1 AND ($2::bigint IS NULL OR id < $2) ORDER BY id DESC LIMIT $3`,
    [worldId, before, limit],
  );
  return rows.map(fromRow).reverse();
}

// How many messages one player has sent since `since` (the spam limit).
export async function sentSince(client: DbClient, worldId: number, accountId: number, since: Date): Promise<number> {
  const { rows } = await client.query<{ n: number }>(
    'SELECT count(*)::int AS n FROM chat_messages WHERE world_id = $1 AND account_id = $2 AND created_at > $3',
    [worldId, accountId, since],
  );
  return rows[0]!.n;
}

export async function lastReadId(client: DbClient, worldId: number, accountId: number): Promise<number> {
  const { rows } = await client.query<{ last_read_id: string }>(
    'SELECT last_read_id FROM chat_reads WHERE world_id = $1 AND account_id = $2',
    [worldId, accountId],
  );
  return rows[0] ? Number(rows[0].last_read_id) : 0;
}

// Read up to `id` (never back).
export async function markChatRead(client: DbClient, worldId: number, accountId: number, id: number): Promise<number> {
  const { rows } = await client.query<{ last_read_id: string }>(
    `INSERT INTO chat_reads (world_id, account_id, last_read_id) VALUES ($1, $2, $3)
     ON CONFLICT (world_id, account_id) DO UPDATE SET last_read_id = GREATEST(chat_reads.last_read_id, EXCLUDED.last_read_id)
     RETURNING last_read_id`,
    [worldId, accountId, id],
  );
  return Number(rows[0]!.last_read_id);
}

// Messages from others the player hasn't read.
export async function unreadCount(client: DbClient, worldId: number, accountId: number): Promise<number> {
  const { rows } = await client.query<{ n: number }>(
    `SELECT count(*)::int AS n FROM chat_messages
     WHERE world_id = $1 AND id > COALESCE((SELECT last_read_id FROM chat_reads WHERE world_id = $1 AND account_id = $2), 0)
       AND account_id <> $2`,
    [worldId, accountId],
  );
  return rows[0]!.n;
}
