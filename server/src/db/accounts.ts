import { createHash, randomBytes } from 'node:crypto';
import type { Db, DbClient } from './pool.js';

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
  return { account, token: await newSession(client, account.id) };
}

// A new sign-in for the account: the token goes to the device, only its hash is kept.
async function newSession(client: DbClient, accountId: number): Promise<string> {
  const token = randomBytes(32).toString('base64url');
  await client.query('INSERT INTO sessions (token_hash, account_id) VALUES ($1, $2)', [hashToken(token), accountId]);
  return token;
}

// Signing in on another device: the signed-in device asks for a code, the
// other types it in. No 0/O or 1/I, so it reads back without doubt;
// 32^10 codes, each good for one sign-in within SIGN_IN_CODE_MINUTES.
export const SIGN_IN_CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
export const SIGN_IN_CODE_LENGTH = 10;
export const SIGN_IN_CODE_MINUTES = 10;

// As typed: any case, spaces and dashes left out.
export function normalizeSignInCode(typed: string): string {
  return typed.toUpperCase().replace(/[^A-Z0-9]/g, '');
}

// A new code for the account (an earlier one it had stops working), shown as ABCDE-FGHJK.
export async function createSignInCode(client: DbClient, accountId: number): Promise<{ code: string; expiresAt: Date }> {
  await client.query('DELETE FROM sign_in_codes WHERE account_id = $1 OR expires_at < now()', [accountId]);
  // 256 is a multiple of 32: every letter is as likely.
  const code = [...randomBytes(SIGN_IN_CODE_LENGTH)].map((b) => SIGN_IN_CODE_ALPHABET[b % SIGN_IN_CODE_ALPHABET.length]).join('');
  const { rows } = await client.query<{ expiresAt: Date }>(
    `INSERT INTO sign_in_codes (code_hash, account_id, expires_at) VALUES ($1, $2, now() + make_interval(mins => $3))
     RETURNING expires_at AS "expiresAt"`,
    [hashToken(code), accountId, SIGN_IN_CODE_MINUTES],
  );
  return { code: `${code.slice(0, 5)}-${code.slice(5)}`, expiresAt: rows[0]!.expiresAt };
}

// Signs in with a code: a new session on its account, and the code is used
// up. Null when it is wrong or has run out.
export async function redeemSignInCode(client: DbClient, typed: string): Promise<{ account: Account; token: string } | null> {
  const { rows } = await client.query<{ accountId: string }>(
    'DELETE FROM sign_in_codes WHERE code_hash = $1 AND expires_at > now() RETURNING account_id AS "accountId"',
    [hashToken(normalizeSignInCode(typed))],
  );
  if (!rows[0]) return null;
  const accountId = Number(rows[0].accountId);
  const { rows: accounts } = await client.query<Account>('SELECT id, display_name AS "displayName", language FROM accounts WHERE id = $1', [accountId]);
  return { account: accounts[0]!, token: await newSession(client, accountId) };
}

// One statement, so it needs no transaction (pass the pool). The session's
// last use is only noted once an hour: most requests then write nothing.
export async function accountForToken(client: DbClient | Db, token: string): Promise<Account | null> {
  const { rows } = await client.query<Account>(
    `WITH touched AS (
       UPDATE sessions SET last_used_at = now()
       WHERE token_hash = $1 AND last_used_at < now() - interval '1 hour'
     )
     SELECT a.id, a.display_name AS "displayName", a.language
     FROM sessions s JOIN accounts a ON a.id = s.account_id
     WHERE s.token_hash = $1`,
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
 * phones, its hand-overs, its bug reports and what it wrote in group chats. Session tokens and sign-in
 * codes are left out: only their hashes are kept, and they are of no use to anyone.
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
    chat: await rows('SELECT to_jsonb(c) AS row FROM chat_messages c WHERE c.account_id = $1 ORDER BY c.id'),
  };
}
