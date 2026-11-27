// The enemy's settlements (migration 092; scheduler/enemySettlements.ts).
import { hex, type Hex } from '../sim/hex.js';
import type { DbClient } from './pool.js';

export type EnemySettlementStatus = 'standing';

export interface EnemySettlement {
  id: number;
  front: string;
  kind: string;
  band: number;
  cell: Hex;
  status: EnemySettlementStatus;
  garrison: Record<string, number>;
  foundedAt: Date;
  // When it may sally again (null: now).
  sallyReadyAt: Date | null;
}

interface Row {
  id: string | number;
  front: string;
  kind: string;
  band: number;
  q: number;
  r: number;
  status: EnemySettlementStatus;
  garrison: Record<string, number>;
  founded_at: Date;
  sally_ready_at: Date | null;
}

export async function listEnemySettlements(client: DbClient, worldId: number): Promise<EnemySettlement[]> {
  const { rows } = await client.query<Row>('SELECT * FROM enemy_settlements WHERE world_id = $1 ORDER BY id', [worldId]);
  return rows.map((r) => ({ id: Number(r.id), front: r.front, kind: r.kind, band: r.band, cell: hex(r.q, r.r), status: r.status, garrison: r.garrison, foundedAt: r.founded_at, sallyReadyAt: r.sally_ready_at }));
}

export async function insertEnemySettlement(client: DbClient, worldId: number, s: { front: string; kind: string; band: number; cell: Hex; foundedAt: Date }): Promise<number> {
  const { rows } = await client.query<{ id: string }>(
    'INSERT INTO enemy_settlements (world_id, front, kind, band, q, r, founded_at) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id',
    [worldId, s.front, s.kind, s.band, s.cell.q, s.cell.r, s.foundedAt],
  );
  return Number(rows[0]!.id);
}

export async function setSallyReady(client: DbClient, id: number, at: Date): Promise<void> {
  await client.query('UPDATE enemy_settlements SET sally_ready_at = $2 WHERE id = $1', [id, at]);
}
