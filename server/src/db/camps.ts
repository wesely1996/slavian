import type { DbClient } from './pool.js';

export interface Camp {
  id: number;
  worldId: number;
  kind: 'bandit' | 'lair';
  front: string;
  q: number;
  r: number;
  units: Record<string, number>;
  status: 'active' | 'cleared';
  waveId: number | null;
  createdAt: Date;
}

interface CampRow {
  id: number;
  world_id: number;
  kind: 'bandit' | 'lair';
  front: string;
  q: number;
  r: number;
  units: Record<string, number>;
  status: 'active' | 'cleared';
  wave_id: number | null;
  created_at: Date;
}

function fromRow(row: CampRow): Camp {
  return {
    id: row.id,
    worldId: row.world_id,
    kind: row.kind,
    front: row.front,
    q: row.q,
    r: row.r,
    units: row.units,
    status: row.status,
    waveId: row.wave_id,
    createdAt: row.created_at,
  };
}

export async function insertCamp(client: DbClient, c: Pick<Camp, 'worldId' | 'kind' | 'front' | 'q' | 'r' | 'units' | 'waveId' | 'createdAt'>): Promise<Camp> {
  const { rows } = await client.query<CampRow>(
    `INSERT INTO camps (world_id, kind, front, q, r, units, wave_id, created_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *`,
    [c.worldId, c.kind, c.front, c.q, c.r, JSON.stringify(c.units), c.waveId, c.createdAt],
  );
  return fromRow(rows[0]!);
}

export async function listCamps(client: DbClient, worldId: number): Promise<Camp[]> {
  const { rows } = await client.query<CampRow>(`SELECT * FROM camps WHERE world_id = $1 AND status = 'active' ORDER BY id`, [worldId]);
  return rows.map(fromRow);
}
