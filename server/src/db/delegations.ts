import { ForbiddenError } from '../errors.js';
import type { DbClient } from './pool.js';

export interface Delegation {
  ownerAccountId: number;
  delegateAccountId: number;
  since: Date;
  until: Date;
}

export interface DelegationEntry {
  ownerAccountId: number;
  delegateAccountId: number;
  villageId: number | null;
  action: string;
  at: Date;
}

const COLUMNS = `owner_account_id::int AS "ownerAccountId", delegate_account_id::int AS "delegateAccountId", since, until`;

export async function setDelegation(client: DbClient, worldId: number, delegation: Delegation): Promise<void> {
  await client.query(
    `INSERT INTO delegations (world_id, owner_account_id, delegate_account_id, since, until) VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (world_id, owner_account_id) DO UPDATE SET delegate_account_id = $3, since = $4, until = $5`,
    [worldId, delegation.ownerAccountId, delegation.delegateAccountId, delegation.since, delegation.until],
  );
}

export async function endDelegation(client: DbClient, worldId: number, ownerAccountId: number): Promise<boolean> {
  const { rowCount } = await client.query('DELETE FROM delegations WHERE world_id = $1 AND owner_account_id = $2', [worldId, ownerAccountId]);
  return rowCount === 1;
}

// Hand-overs still running at `at`.
export async function activeDelegations(client: DbClient, worldId: number, at: Date): Promise<Delegation[]> {
  const { rows } = await client.query<Delegation>(`SELECT ${COLUMNS} FROM delegations WHERE world_id = $1 AND until > $2 ORDER BY since`, [worldId, at]);
  return rows;
}

export async function recentDelegationLog(client: DbClient, worldId: number, limit = 30): Promise<DelegationEntry[]> {
  const { rows } = await client.query<DelegationEntry>(
    `SELECT owner_account_id::int AS "ownerAccountId", delegate_account_id::int AS "delegateAccountId", village_id::int AS "villageId", action, at
     FROM delegation_log WHERE world_id = $1 ORDER BY at DESC, id DESC LIMIT $2`,
    [worldId, limit],
  );
  return rows;
}

// May `actor` command what `owner` owns? Their own, or a teammate's who
// handed it to them; what a delegate does is logged for the owner to see.
export async function authorize(
  client: DbClient,
  input: { worldId: number; ownerAccountId: number | null; actorAccountId: number; at: Date; action: string; villageId?: number; refusal?: string },
): Promise<void> {
  if (input.ownerAccountId !== null && input.ownerAccountId === input.actorAccountId) return;
  const delegation =
    input.ownerAccountId === null
      ? undefined
      : (await activeDelegations(client, input.worldId, input.at)).find(
          (d) => d.ownerAccountId === input.ownerAccountId && d.delegateAccountId === input.actorAccountId,
        );
  if (!delegation) throw new ForbiddenError(input.refusal ?? 'Not your village');
  await client.query(
    'INSERT INTO delegation_log (world_id, owner_account_id, delegate_account_id, village_id, action, at) VALUES ($1, $2, $3, $4, $5, $6)',
    [input.worldId, delegation.ownerAccountId, delegation.delegateAccountId, input.villageId ?? null, input.action, input.at],
  );
}
