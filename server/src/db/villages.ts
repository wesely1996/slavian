import type { Stance } from '../data/index.js';
import type { Resources } from '../sim/resources.js';
import type { TrainingBatch } from '../sim/training.js';
import type { Plot, QueuedBuild, VillageState } from '../sim/village.js';
import { NotFoundError } from '../errors.js';
import type { DbClient } from './pool.js';

export interface Village {
  id: number;
  worldId: number;
  ownerAccountId: number | null;
  name: string;
  q: number;
  r: number;
  state: VillageState;
}

interface VillageRow {
  id: number;
  world_id: number;
  owner_account_id: number | null;
  name: string;
  q: number;
  r: number;
  levels: Record<string, number>;
  // Null only for villages saved before plots existed (see upgrades.ts).
  plots: Record<string, Plot> | null;
  amounts: Resources;
  rates_per_hour: Resources;
  capacity: Resources;
  settled_at: Date;
  queue: { plot?: string; building: string; targetLevel: number; startsAt: string; completesAt: string }[];
  garrison: Record<string, number>;
  training: { unit: string; count: number; startsAt: string; perUnitMs: number }[];
  away: Record<string, number>;
  stance: Stance;
  besieged: boolean;
  admin_upkeep: number;
  bonuses: Record<string, number>;
}

function fromRow(row: VillageRow): Village {
  const queue: QueuedBuild[] = row.queue.map((item) => ({
    plot: item.plot ?? '',
    building: item.building,
    targetLevel: item.targetLevel,
    startsAt: new Date(item.startsAt),
    completesAt: new Date(item.completesAt),
  }));
  const training: TrainingBatch[] = row.training.map((batch) => ({
    unit: batch.unit,
    count: batch.count,
    startsAt: new Date(batch.startsAt),
    perUnitMs: batch.perUnitMs,
  }));
  return {
    id: row.id,
    worldId: row.world_id,
    ownerAccountId: row.owner_account_id,
    name: row.name,
    q: row.q,
    r: row.r,
    state: {
      plots: row.plots ?? {},
      levels: row.levels,
      queue,
      garrison: row.garrison,
      training,
      away: row.away,
      stance: row.stance,
      besieged: row.besieged,
      adminUpkeep: Number(row.admin_upkeep),
      bonuses: row.bonuses,
      ledger: {
        amounts: row.amounts,
        ratesPerHour: row.rates_per_hour,
        capacity: row.capacity,
        settledAt: row.settled_at,
      },
    },
  };
}

export async function insertVillage(
  client: DbClient,
  village: Omit<Village, 'id'>,
): Promise<Village> {
  const { state } = village;
  const { rows } = await client.query<VillageRow>(
    `INSERT INTO villages
       (world_id, owner_account_id, name, q, r, levels, amounts, rates_per_hour, capacity, settled_at, queue, garrison, training, away, stance, plots, besieged, admin_upkeep, bonuses)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19)
     RETURNING *`,
    [
      village.worldId,
      village.ownerAccountId,
      village.name,
      village.q,
      village.r,
      JSON.stringify(state.levels),
      JSON.stringify(state.ledger.amounts),
      JSON.stringify(state.ledger.ratesPerHour),
      JSON.stringify(state.ledger.capacity),
      state.ledger.settledAt,
      JSON.stringify(state.queue),
      JSON.stringify(state.garrison),
      JSON.stringify(state.training),
      JSON.stringify(state.away),
      state.stance,
      JSON.stringify(state.plots),
      state.besieged,
      state.adminUpkeep,
      JSON.stringify(state.bonuses),
    ],
  );
  return fromRow(rows[0]!);
}

export async function loadVillage(client: DbClient, id: number): Promise<Village> {
  const { rows } = await client.query<VillageRow>('SELECT * FROM villages WHERE id = $1', [id]);
  if (!rows[0]) throw new NotFoundError(`Village ${id} not found`);
  return fromRow(rows[0]);
}

export async function listVillages(client: DbClient, worldId: number): Promise<Village[]> {
  const { rows } = await client.query<VillageRow>('SELECT * FROM villages WHERE world_id = $1 ORDER BY id', [worldId]);
  return rows.map(fromRow);
}

export async function saveVillageState(client: DbClient, id: number, state: VillageState): Promise<void> {
  await client.query(
    `UPDATE villages
     SET levels = $2, amounts = $3, rates_per_hour = $4, capacity = $5, settled_at = $6, queue = $7,
         garrison = $8, training = $9, away = $10, stance = $11, plots = $12, besieged = $13, admin_upkeep = $14, bonuses = $15
     WHERE id = $1`,
    [
      id,
      JSON.stringify(state.levels),
      JSON.stringify(state.ledger.amounts),
      JSON.stringify(state.ledger.ratesPerHour),
      JSON.stringify(state.ledger.capacity),
      state.ledger.settledAt,
      JSON.stringify(state.queue),
      JSON.stringify(state.garrison),
      JSON.stringify(state.training),
      JSON.stringify(state.away),
      state.stance,
      JSON.stringify(state.plots),
      state.besieged,
      state.adminUpkeep,
      JSON.stringify(state.bonuses),
    ],
  );
}
