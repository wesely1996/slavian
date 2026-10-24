import type { DbClient } from './pool.js';

export interface ResearchEntry {
  worldId: number;
  accountId: number;
  tech: string;
  status: 'researching' | 'done';
  villageId: number | null;
  startedAt: Date;
  completesAt: Date;
}

interface ResearchRow {
  world_id: number;
  account_id: number;
  tech: string;
  status: 'researching' | 'done';
  village_id: number | null;
  started_at: Date;
  completes_at: Date;
}

function fromRow(row: ResearchRow): ResearchEntry {
  return {
    worldId: row.world_id,
    accountId: row.account_id,
    tech: row.tech,
    status: row.status,
    villageId: row.village_id,
    startedAt: row.started_at,
    completesAt: row.completes_at,
  };
}

export async function listResearch(client: DbClient, worldId: number, accountId?: number): Promise<ResearchEntry[]> {
  const { rows } = await client.query<ResearchRow>(
    `SELECT * FROM research WHERE world_id = $1 AND ($2::bigint IS NULL OR account_id = $2)
     ORDER BY account_id, completes_at, tech`,
    [worldId, accountId ?? null],
  );
  return rows.map(fromRow);
}

export async function startResearch(client: DbClient, entry: Omit<ResearchEntry, 'status'>): Promise<ResearchEntry> {
  const { rows } = await client.query<ResearchRow>(
    `INSERT INTO research (world_id, account_id, tech, status, village_id, started_at, completes_at)
     VALUES ($1, $2, $3, 'researching', $4, $5, $6) RETURNING *`,
    [entry.worldId, entry.accountId, entry.tech, entry.villageId, entry.startedAt, entry.completesAt],
  );
  return fromRow(rows[0]!);
}

export async function finishResearch(client: DbClient, worldId: number, accountId: number, tech: string): Promise<boolean> {
  const { rowCount } = await client.query(
    `UPDATE research SET status = 'done' WHERE world_id = $1 AND account_id = $2 AND tech = $3 AND status = 'researching'`,
    [worldId, accountId, tech],
  );
  return (rowCount ?? 0) > 0;
}

// Research a player's Academies brought in, as of `settledAt` (null: never
// settled yet).
export interface ResearchPoints {
  amount: number;
  settledAt: Date | null;
}

export async function loadResearchPoints(client: DbClient, worldId: number, accountId: number): Promise<ResearchPoints> {
  const { rows } = await client.query<{ research_points: number; research_settled_at: Date | null }>(
    'SELECT research_points, research_settled_at FROM world_members WHERE world_id = $1 AND account_id = $2',
    [worldId, accountId],
  );
  return { amount: rows[0]?.research_points ?? 0, settledAt: rows[0]?.research_settled_at ?? null };
}

export async function saveResearchPoints(client: DbClient, worldId: number, accountId: number, points: ResearchPoints): Promise<void> {
  await client.query('UPDATE world_members SET research_points = $3, research_settled_at = $4 WHERE world_id = $1 AND account_id = $2', [
    worldId,
    accountId,
    points.amount,
    points.settledAt,
  ]);
}
