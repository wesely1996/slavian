import { createHash, randomBytes } from 'node:crypto';
import type { DbClient } from './pool.js';

export interface Account {
  id: number;
  displayName: string;
  language: string;
}

export function hashToken(token: string): Buffer {
  return createHash('sha256').update(token).digest();
}

export async function createGuestAccount(
  client: DbClient,
  displayName: string,
): Promise<{ account: Account; token: string }> {
  const { rows } = await client.query<Account>(
    'INSERT INTO accounts (display_name) VALUES ($1) RETURNING id, display_name AS "displayName", language',
    [displayName],
  );
  const account = rows[0]!;
  const token = randomBytes(32).toString('base64url');
  await client.query('INSERT INTO sessions (token_hash, account_id) VALUES ($1, $2)', [hashToken(token), account.id]);
  return { account, token };
}

export async function accountForToken(client: DbClient, token: string): Promise<Account | null> {
  const { rows } = await client.query<Account>(
    `UPDATE sessions s SET last_used_at = now()
     FROM accounts a
     WHERE s.token_hash = $1 AND a.id = s.account_id
     RETURNING a.id, a.display_name AS "displayName", a.language`,
    [hashToken(token)],
  );
  return rows[0] ?? null;
}

export async function renameAccount(client: DbClient, accountId: number, displayName: string): Promise<Account> {
  const { rows } = await client.query<Account>(
    'UPDATE accounts SET display_name = $2 WHERE id = $1 RETURNING id, display_name AS "displayName", language',
    [accountId, displayName],
  );
  return rows[0]!;
}

/** The app reports its language so server notices can be rendered in it. */
export async function setAccountLanguage(client: DbClient, accountId: number, language: string): Promise<void> {
  await client.query('UPDATE accounts SET language = $2 WHERE id = $1', [accountId, language]);
}

export async function accountLanguage(client: DbClient, accountId: number): Promise<string> {
  const { rows } = await client.query<{ language: string }>('SELECT language FROM accounts WHERE id = $1', [accountId]);
  return rows[0]?.language ?? 'en';
}

/** Deletes an account and everything cascading from it (sessions, memberships, devices). */
export async function deleteAccount(client: DbClient, accountId: number): Promise<void> {
  await client.query('DELETE FROM accounts WHERE id = $1', [accountId]);
}

/**
 * Everything kept about an account, for its owner to download (GET
 * /v1/me/export, docs/privacy.md): the account with its settings, the worlds
 * it plays in, its villages, armies, heroes and research, its inbox, its
 * phones, its hand-overs and its bug reports. Session tokens are left out:
 * only their hashes are kept, and they are of no use to anyone.
 */
export async function exportAccount(client: DbClient, accountId: number): Promise<Record<string, unknown>> {
  const rows = async (sql: string) => (await client.query<{ row: unknown }>(sql, [accountId])).rows.map((r) => r.row);
  const [settings] = await rows('SELECT to_jsonb(a) AS row FROM accounts a WHERE a.id = $1');
  return {
    settings,
    worlds: await rows(
      `SELECT to_jsonb(m) || jsonb_build_object('worldName', w.name) AS row
       FROM world_members m JOIN worlds w ON w.id = m.world_id WHERE m.account_id = $1 ORDER BY m.world_id`,
    ),
    villages: await rows('SELECT to_jsonb(v) AS row FROM villages v WHERE v.owner_account_id = $1 ORDER BY v.id'),
    armies: await rows('SELECT to_jsonb(a) AS row FROM armies a WHERE a.owner_account_id = $1 ORDER BY a.id'),
    heroes: await rows('SELECT to_jsonb(h) AS row FROM heroes h WHERE h.account_id = $1'),
    research: await rows('SELECT to_jsonb(r) AS row FROM research r WHERE r.account_id = $1'),
    notifications: await rows('SELECT to_jsonb(n) AS row FROM notifications n WHERE n.account_id = $1 ORDER BY n.id'),
    devices: await rows('SELECT to_jsonb(d) AS row FROM devices d WHERE d.account_id = $1'),
    delegations: await rows('SELECT to_jsonb(d) AS row FROM delegations d WHERE d.owner_account_id = $1 OR d.delegate_account_id = $1'),
    reports: await rows('SELECT to_jsonb(r) AS row FROM reports r WHERE r.account_id = $1 ORDER BY r.id'),
  };
}
