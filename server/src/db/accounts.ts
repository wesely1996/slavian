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
