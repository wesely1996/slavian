import { NotFoundError } from '../errors.js';
import type { ScoutReport } from '../sim/scouting.js';
import type { DbClient } from './pool.js';

export type MissionStatus = 'outbound' | 'returning' | 'done';

export interface ScoutMission {
  id: number;
  worldId: number;
  villageId: number;
  waveId: number;
  sent: number;
  survivors: number | null;
  status: MissionStatus;
  target: { q: number; r: number };
  departsAt: Date;
  arrivesAt: Date;
  returnsAt: Date;
  report: ScoutReport | null;
}

interface MissionRow {
  id: number;
  world_id: number;
  village_id: number;
  wave_id: number;
  sent: number;
  survivors: number | null;
  status: MissionStatus;
  target_q: number;
  target_r: number;
  departs_at: Date;
  arrives_at: Date;
  returns_at: Date;
  report: ScoutReport | null;
}

function fromRow(row: MissionRow): ScoutMission {
  return {
    id: row.id,
    worldId: row.world_id,
    villageId: row.village_id,
    waveId: row.wave_id,
    sent: row.sent,
    survivors: row.survivors,
    status: row.status,
    target: { q: row.target_q, r: row.target_r },
    departsAt: row.departs_at,
    arrivesAt: row.arrives_at,
    returnsAt: row.returns_at,
    report: row.report,
  };
}

export async function insertMission(
  client: DbClient,
  mission: Omit<ScoutMission, 'id' | 'survivors' | 'status' | 'report'>,
): Promise<ScoutMission> {
  const { rows } = await client.query<MissionRow>(
    `INSERT INTO scout_missions (world_id, village_id, wave_id, sent, target_q, target_r, departs_at, arrives_at, returns_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING *`,
    [
      mission.worldId,
      mission.villageId,
      mission.waveId,
      mission.sent,
      mission.target.q,
      mission.target.r,
      mission.departsAt,
      mission.arrivesAt,
      mission.returnsAt,
    ],
  );
  return fromRow(rows[0]!);
}

export async function loadMission(client: DbClient, id: number): Promise<ScoutMission> {
  const { rows } = await client.query<MissionRow>('SELECT * FROM scout_missions WHERE id = $1', [id]);
  if (!rows[0]) throw new NotFoundError(`Scout mission ${id} not found`);
  return fromRow(rows[0]);
}

export async function recordReport(client: DbClient, id: number, report: ScoutReport): Promise<void> {
  await client.query(
    "UPDATE scout_missions SET status = 'returning', survivors = $2, report = $3 WHERE id = $1",
    [id, report.survivors, JSON.stringify(report)],
  );
}

export async function markMissionDone(client: DbClient, id: number): Promise<void> {
  await client.query("UPDATE scout_missions SET status = 'done' WHERE id = $1", [id]);
}

// Missions about waves still on the board, newest first.
export async function listMissions(client: DbClient, worldId: number): Promise<ScoutMission[]> {
  const { rows } = await client.query<MissionRow>(
    `SELECT m.* FROM scout_missions m JOIN waves w ON w.id = m.wave_id
     WHERE m.world_id = $1 AND (w.status <> 'dispersed' OR m.status <> 'done')
     ORDER BY m.departs_at DESC, m.id DESC`,
    [worldId],
  );
  return rows.map(fromRow);
}
