import type { Resources } from '../sim/resources.js';
import type { DbClient } from './pool.js';

export type BountyStatus = 'open' | 'taken' | 'cancelled';

// A bounty on the Market's board (migration 063).
export interface Bounty {
  id: number;
  worldId: number;
  villageId: number;
  ownerAccountId: number | null;
  // What the poster gives (paid), what they ask for, and the fee they paid.
  offer: Resources;
  want: Resources;
  fee: Resources;
  status: BountyStatus;
  createdAt: Date;
  closedAt: Date | null;
  takenByVillageId: number | null;
}

interface BountyRow {
  id: number;
  world_id: number;
  village_id: number;
  owner_account_id: number | null;
  offer: Resources;
  want: Resources;
  fee: Resources;
  status: BountyStatus;
  created_at: Date;
  closed_at: Date | null;
  taken_by_village_id: number | null;
}

function fromRow(row: BountyRow): Bounty {
  return {
    id: Number(row.id),
    worldId: Number(row.world_id),
    villageId: Number(row.village_id),
    ownerAccountId: row.owner_account_id === null ? null : Number(row.owner_account_id),
    offer: row.offer,
    want: row.want,
    fee: row.fee,
    status: row.status,
    createdAt: row.created_at,
    closedAt: row.closed_at,
    takenByVillageId: row.taken_by_village_id === null ? null : Number(row.taken_by_village_id),
  };
}

export async function insertBounty(client: DbClient, b: Pick<Bounty, 'worldId' | 'villageId' | 'ownerAccountId' | 'offer' | 'want' | 'fee' | 'createdAt'>): Promise<Bounty> {
  const { rows } = await client.query<BountyRow>(
    `INSERT INTO bounties (world_id, village_id, owner_account_id, offer, want, fee, created_at) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
    [b.worldId, b.villageId, b.ownerAccountId, JSON.stringify(b.offer), JSON.stringify(b.want), JSON.stringify(b.fee), b.createdAt],
  );
  return fromRow(rows[0]!);
}

export async function loadBounty(client: DbClient, id: number): Promise<Bounty | null> {
  const { rows } = await client.query<BountyRow>('SELECT * FROM bounties WHERE id = $1', [id]);
  return rows[0] ? fromRow(rows[0]) : null;
}

export async function closeBounty(client: DbClient, id: number, status: 'taken' | 'cancelled', at: Date, takenBy: number | null): Promise<void> {
  await client.query('UPDATE bounties SET status = $2, closed_at = $3, taken_by_village_id = $4 WHERE id = $1', [id, status, at, takenBy]);
}

// The open bounties of a world, oldest first.
export async function openBounties(client: DbClient, worldId: number): Promise<Bounty[]> {
  const { rows } = await client.query<BountyRow>(`SELECT * FROM bounties WHERE world_id = $1 AND status = 'open' ORDER BY id`, [worldId]);
  return rows.map(fromRow);
}

export async function openBountiesOf(client: DbClient, villageId: number): Promise<number> {
  const { rows } = await client.query<{ n: string }>(`SELECT count(*) AS n FROM bounties WHERE village_id = $1 AND status = 'open'`, [villageId]);
  return Number(rows[0]!.n);
}
