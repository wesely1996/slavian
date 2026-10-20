// Bug reports: the player's message plus the game state the app captured, so
// the developer can reproduce a problem from the report alone.
import type { DbClient } from './pool.js';

export interface BugReport {
  message: string;
  worldId: number | null;
  state: unknown;
}

export async function saveReport(client: DbClient, accountId: number | null, report: BugReport): Promise<number> {
  const { rows } = await client.query<{ id: number }>(
    'INSERT INTO reports (account_id, world_id, message, state) VALUES ($1, $2, $3, $4) RETURNING id',
    [accountId, report.worldId, report.message, JSON.stringify(report.state ?? {})],
  );
  return rows[0]!.id;
}
