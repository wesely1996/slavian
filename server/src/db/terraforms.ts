import { hex, type Hex } from '../sim/hex.js';
import type { DbClient } from './pool.js';

// Land being reshaped (field.json terraform): one work to a hex.
export interface Terraform {
  cell: Hex;
  action: string;
  villageId: number | null;
  completesAt: Date;
  // A fire: 0 where it was set, +1 for each hex it spread to.
  generation: number;
  // A river dug: the neighbouring hex it runs toward (along their edge).
  toward?: Hex | null;
}

interface Row {
  q: number;
  r: number;
  action: string;
  village_id: string | null;
  completes_at: Date;
  generation: number;
  tq: number | null;
  tr: number | null;
}

const fromRow = (r: Row): Terraform => ({
  cell: hex(r.q, r.r),
  action: r.action,
  villageId: r.village_id === null ? null : Number(r.village_id),
  completesAt: r.completes_at,
  generation: r.generation,
  toward: r.tq === null || r.tr === null ? null : hex(r.tq, r.tr),
});

export async function listTerraforms(client: DbClient, worldId: number): Promise<Terraform[]> {
  const { rows } = await client.query<Row>('SELECT * FROM terraforms WHERE world_id = $1 ORDER BY q, r', [worldId]);
  return rows.map(fromRow);
}

export async function terraformAt(client: DbClient, worldId: number, cell: Hex): Promise<Terraform | null> {
  const { rows } = await client.query<Row>('SELECT * FROM terraforms WHERE world_id = $1 AND q = $2 AND r = $3', [worldId, cell.q, cell.r]);
  return rows[0] ? fromRow(rows[0]) : null;
}

export async function insertTerraform(client: DbClient, worldId: number, work: Terraform): Promise<void> {
  await client.query('INSERT INTO terraforms (world_id, q, r, action, village_id, completes_at, generation, tq, tr) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)', [
    worldId,
    work.cell.q,
    work.cell.r,
    work.action,
    work.villageId,
    work.completesAt,
    work.generation,
    work.toward?.q ?? null,
    work.toward?.r ?? null,
  ]);
}

export async function deleteTerraform(client: DbClient, worldId: number, cell: Hex): Promise<void> {
  await client.query('DELETE FROM terraforms WHERE world_id = $1 AND q = $2 AND r = $3', [worldId, cell.q, cell.r]);
}
