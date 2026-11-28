// The enemy's war bands (migration 093; scheduler/enemyForces.ts).
import type { PathStep } from '../sim/waves.js';
import type { DbClient } from './pool.js';

// 'hunting' an army its scouts spotted, 'patrolling' between its front's
// settlements, 'returning' home.
export type EnemyBandStatus = 'hunting' | 'patrolling' | 'returning';
export type EnemyBandKind = 'sally' | 'patrol';

export interface EnemyBand {
  id: number;
  front: string;
  kind: EnemyBandKind;
  settlementId: number | null;
  units: Record<string, number>;
  scouts: number;
  status: EnemyBandStatus;
  path: PathStep[];
  departsAt: Date;
  arrivesAt: Date;
  targetArmyId: number | null;
}

interface Row {
  id: string | number;
  front: string;
  kind: EnemyBandKind;
  settlement_id: string | number | null;
  units: Record<string, number>;
  scouts: number;
  status: EnemyBandStatus;
  path: PathStep[];
  departs_at: Date;
  arrives_at: Date;
  target_army_id: string | number | null;
}

const fromRow = (r: Row): EnemyBand => ({
  id: Number(r.id),
  front: r.front,
  kind: r.kind,
  settlementId: r.settlement_id === null ? null : Number(r.settlement_id),
  units: r.units,
  scouts: r.scouts,
  status: r.status,
  path: r.path,
  departsAt: r.departs_at,
  arrivesAt: r.arrives_at,
  targetArmyId: r.target_army_id === null ? null : Number(r.target_army_id),
});

export async function listEnemyBands(client: DbClient, worldId: number): Promise<EnemyBand[]> {
  const { rows } = await client.query<Row>('SELECT * FROM enemy_bands WHERE world_id = $1 ORDER BY id', [worldId]);
  return rows.map(fromRow);
}

export async function loadEnemyBand(client: DbClient, id: number): Promise<EnemyBand | null> {
  const { rows } = await client.query<Row>('SELECT * FROM enemy_bands WHERE id = $1', [id]);
  return rows[0] ? fromRow(rows[0]) : null;
}

export async function insertEnemyBand(client: DbClient, worldId: number, b: Omit<EnemyBand, 'id'>): Promise<number> {
  const { rows } = await client.query<{ id: string }>(
    `INSERT INTO enemy_bands (world_id, front, kind, settlement_id, units, scouts, status, path, departs_at, arrives_at, target_army_id)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11) RETURNING id`,
    [worldId, b.front, b.kind, b.settlementId, JSON.stringify(b.units), b.scouts, b.status, JSON.stringify(b.path), b.departsAt, b.arrivesAt, b.targetArmyId],
  );
  return Number(rows[0]!.id);
}

export async function saveEnemyBand(client: DbClient, b: EnemyBand): Promise<void> {
  await client.query(
    'UPDATE enemy_bands SET units = $2, status = $3, path = $4, departs_at = $5, arrives_at = $6, target_army_id = $7, settlement_id = $8 WHERE id = $1',
    [b.id, JSON.stringify(b.units), b.status, JSON.stringify(b.path), b.departsAt, b.arrivesAt, b.targetArmyId, b.settlementId],
  );
}

export async function deleteEnemyBand(client: DbClient, id: number): Promise<void> {
  await client.query('DELETE FROM enemy_bands WHERE id = $1', [id]);
}
