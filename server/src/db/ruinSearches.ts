import { NotFoundError } from '../errors.js';
import type { PlacedSite } from '../sim/sites.js';
import type { DbClient } from './pool.js';

// Scouts out searching for a forgotten ruin (data/scouting.json `ruinSearch`).
export interface RuinSearch {
  id: number;
  worldId: number;
  villageId: number;
  scouts: number;
  status: 'out' | 'done';
  departsAt: Date;
  returnsAt: Date;
  // The site they found, once back (null: nothing, or not back yet).
  foundSiteId: number | null;
  // Where they will find a ruin, settled when they set out (null: nowhere).
  plan: PlacedSite | null;
}

interface Row {
  id: number;
  world_id: number;
  village_id: number;
  scouts: number;
  status: 'out' | 'done';
  departs_at: Date;
  returns_at: Date;
  found_site_id: number | null;
  plan: PlacedSite | null;
}

function fromRow(row: Row): RuinSearch {
  return {
    id: row.id,
    worldId: row.world_id,
    villageId: row.village_id,
    scouts: row.scouts,
    status: row.status,
    departsAt: row.departs_at,
    returnsAt: row.returns_at,
    foundSiteId: row.found_site_id,
    plan: row.plan ?? null,
  };
}

export async function insertRuinSearch(client: DbClient, s: Pick<RuinSearch, 'worldId' | 'villageId' | 'scouts' | 'departsAt' | 'returnsAt'>): Promise<RuinSearch> {
  const { rows } = await client.query<Row>(
    'INSERT INTO ruin_searches (world_id, village_id, scouts, departs_at, returns_at) VALUES ($1, $2, $3, $4, $5) RETURNING *',
    [s.worldId, s.villageId, s.scouts, s.departsAt, s.returnsAt],
  );
  return fromRow(rows[0]!);
}

// Where (or whether) the search finds a ruin, and so when it is back.
export async function planRuinSearch(client: DbClient, id: number, plan: PlacedSite | null, returnsAt: Date): Promise<RuinSearch> {
  const { rows } = await client.query<Row>('UPDATE ruin_searches SET plan = $2, returns_at = $3 WHERE id = $1 RETURNING *', [
    id,
    plan === null ? null : JSON.stringify(plan),
    returnsAt,
  ]);
  return fromRow(rows[0]!);
}

export async function loadRuinSearch(client: DbClient, id: number): Promise<RuinSearch> {
  const { rows } = await client.query<Row>('SELECT * FROM ruin_searches WHERE id = $1', [id]);
  if (!rows[0]) throw new NotFoundError(`Ruin search ${id} not found`);
  return fromRow(rows[0]);
}

export async function finishRuinSearch(client: DbClient, id: number, foundSiteId: number | null): Promise<void> {
  await client.query(`UPDATE ruin_searches SET status = 'done', found_site_id = $2 WHERE id = $1`, [id, foundSiteId]);
}

// When each player's scouts last set out to search (by account id), over
// all their villages.
export async function lastRuinSearches(client: DbClient, worldId: number): Promise<Map<number, Date>> {
  const { rows } = await client.query<{ account_id: number; at: Date }>(
    `SELECT v.owner_account_id AS account_id, max(s.departs_at) AS at FROM ruin_searches s JOIN villages v ON v.id = s.village_id
     WHERE s.world_id = $1 AND v.owner_account_id IS NOT NULL GROUP BY v.owner_account_id`,
    [worldId],
  );
  return new Map(rows.map((r) => [Number(r.account_id), r.at]));
}

// Searches still out, plus the five latest back, newest first.
export async function listRuinSearches(client: DbClient, worldId: number): Promise<RuinSearch[]> {
  const { rows } = await client.query<Row>(
    `(SELECT * FROM ruin_searches WHERE world_id = $1 AND status = 'out')
     UNION ALL
     (SELECT * FROM ruin_searches WHERE world_id = $1 AND status = 'done' ORDER BY returns_at DESC, id DESC LIMIT 5)
     ORDER BY departs_at DESC, id DESC`,
    [worldId],
  );
  return rows.map(fromRow);
}
