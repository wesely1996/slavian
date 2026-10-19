import type { Find, PlacedSite } from '../sim/sites.js';
import type { DbClient } from './pool.js';

export interface Site {
  id: number;
  worldId: number;
  kind: string;
  q: number;
  r: number;
  guardians: Record<string, number>;
  guardiansSeen: boolean;
  status: 'unexplored' | 'explored';
  exploredBy: number | null;
  find: Find | null;
  exploredAt: Date | null;
}

interface SiteRow {
  id: number;
  world_id: number;
  kind: string;
  q: number;
  r: number;
  guardians: Record<string, number>;
  guardians_seen: boolean;
  status: 'unexplored' | 'explored';
  explored_by: number | null;
  find: Find | null;
  explored_at: Date | null;
}

function fromRow(row: SiteRow): Site {
  return {
    id: row.id,
    worldId: row.world_id,
    kind: row.kind,
    q: row.q,
    r: row.r,
    guardians: row.guardians,
    guardiansSeen: row.guardians_seen,
    status: row.status,
    exploredBy: row.explored_by,
    find: row.find,
    exploredAt: row.explored_at,
  };
}

export async function insertSites(client: DbClient, worldId: number, sites: readonly PlacedSite[]): Promise<void> {
  for (const site of sites) {
    await client.query('INSERT INTO sites (world_id, kind, q, r, guardians) VALUES ($1, $2, $3, $4, $5) ON CONFLICT DO NOTHING', [
      worldId,
      site.kind,
      site.q,
      site.r,
      JSON.stringify(site.guardians),
    ]);
  }
}

export async function listSites(client: DbClient, worldId: number): Promise<Site[]> {
  const { rows } = await client.query<SiteRow>('SELECT * FROM sites WHERE world_id = $1 ORDER BY id', [worldId]);
  return rows.map(fromRow);
}

export async function loadSite(client: DbClient, id: number): Promise<Site | null> {
  const { rows } = await client.query<SiteRow>('SELECT * FROM sites WHERE id = $1', [id]);
  return rows[0] ? fromRow(rows[0]) : null;
}

export async function siteAt(client: DbClient, worldId: number, q: number, r: number): Promise<Site | null> {
  const { rows } = await client.query<SiteRow>('SELECT * FROM sites WHERE world_id = $1 AND q = $2 AND r = $3', [worldId, q, r]);
  return rows[0] ? fromRow(rows[0]) : null;
}

export async function saveGuardians(client: DbClient, id: number, guardians: Record<string, number>): Promise<void> {
  await client.query('UPDATE sites SET guardians = $2, guardians_seen = true WHERE id = $1', [id, JSON.stringify(guardians)]);
}

export async function markExplored(client: DbClient, id: number, accountId: number | null, find: Find, at: Date): Promise<void> {
  await client.query(`UPDATE sites SET status = 'explored', explored_by = $2, find = $3, explored_at = $4 WHERE id = $1`, [
    id,
    accountId,
    JSON.stringify(find),
    at,
  ]);
}

export interface Scroll {
  scroll: string;
  accountId: number | null;
  siteId: number | null;
  foundAt: Date;
}

export async function listScrolls(client: DbClient, worldId: number): Promise<Scroll[]> {
  const { rows } = await client.query<{ scroll: string; account_id: number | null; site_id: number | null; found_at: Date }>(
    'SELECT scroll, account_id, site_id, found_at FROM lore WHERE world_id = $1 ORDER BY found_at, scroll',
    [worldId],
  );
  return rows.map((row) => ({ scroll: row.scroll, accountId: row.account_id, siteId: row.site_id, foundAt: row.found_at }));
}

export async function addScroll(client: DbClient, worldId: number, scroll: Scroll): Promise<void> {
  await client.query('INSERT INTO lore (world_id, scroll, account_id, site_id, found_at) VALUES ($1, $2, $3, $4, $5) ON CONFLICT DO NOTHING', [
    worldId,
    scroll.scroll,
    scroll.accountId,
    scroll.siteId,
    scroll.foundAt,
  ]);
}
