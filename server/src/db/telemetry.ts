// Light telemetry (PLAN.md §13): run start and end (outcome, cause of a
// loss, the bridge stage reached) and every wave's battle. No personal data:
// a world's id, counts and outcomes only. Read with `npm run telemetry`.
import { findBridge } from './bridges.js';
import type { DbClient } from './pool.js';
import { runSummary } from './runs.js';
import { getWorld, type World } from './worlds.js';

export type TelemetryKind = 'run_start' | 'run_end' | 'wave_result';

export async function record(client: DbClient, worldId: number, kind: TelemetryKind, data: Record<string, unknown>, at: Date): Promise<void> {
  await client.query('INSERT INTO telemetry (world_id, kind, data, at) VALUES ($1, $2, $3, $4)', [worldId, kind, JSON.stringify(data), at]);
}

// A run has ended (the world is already won or lost): how it went, without
// its players' names. `cause` names the front that struck the last blow.
export async function recordRunEnd(client: DbClient, worldId: number, at: Date, cause: string | null = null): Promise<void> {
  const world: World = await getWorld(client, worldId);
  const summary = await runSummary(client, world);
  if (!summary) return;
  const { members, ...counts } = summary;
  await record(
    client,
    worldId,
    'run_end',
    {
      ...counts,
      players: members.length,
      difficulty: world.difficulty,
      speed: world.speed,
      bridgeStage: (await findBridge(client, worldId))?.stage ?? 0,
      sanctity: world.sanctity,
      ...(cause ? { cause } : {}),
    },
    at,
  );
}

export interface TelemetrySummary {
  runs: { started: number; won: number; lost: number; winRate: number | null };
  // Losses by the front that struck the last blow.
  lostTo: Record<string, number>;
  // How far the bridge got, by outcome.
  bridgeStage: { won: number | null; lost: number | null };
  // Wave battles by front: how many, and the share the defenders held.
  waves: Record<string, { battles: number; held: number }>;
}

// The numbers since `since`, for balancing (`npm run telemetry`).
export async function telemetrySummary(client: DbClient, since: Date): Promise<TelemetrySummary> {
  const { rows } = await client.query<{ kind: TelemetryKind; data: Record<string, unknown> }>(
    'SELECT kind, data FROM telemetry WHERE at >= $1 ORDER BY at',
    [since],
  );
  const ends = rows.filter((r) => r.kind === 'run_end').map((r) => r.data);
  const won = ends.filter((d) => d.outcome === 'won');
  const lost = ends.filter((d) => d.outcome === 'lost');
  const mean = (list: Record<string, unknown>[]) =>
    list.length ? Math.round((list.reduce((sum, d) => sum + Number(d.bridgeStage ?? 0), 0) / list.length) * 10) / 10 : null;
  const lostTo: Record<string, number> = {};
  for (const d of lost) lostTo[String(d.cause ?? 'unknown')] = (lostTo[String(d.cause ?? 'unknown')] ?? 0) + 1;
  const waves: Record<string, { battles: number; held: number }> = {};
  for (const r of rows.filter((x) => x.kind === 'wave_result')) {
    const front = String(r.data.front);
    const entry = (waves[front] ??= { battles: 0, held: 0 });
    entry.battles++;
    if (r.data.outcome === 'held') entry.held++;
  }
  return {
    runs: {
      started: rows.filter((r) => r.kind === 'run_start').length,
      won: won.length,
      lost: lost.length,
      winRate: ends.length ? Math.round((won.length / ends.length) * 100) / 100 : null,
    },
    lostTo,
    bridgeStage: { won: mean(won), lost: mean(lost) },
    waves,
  };
}
