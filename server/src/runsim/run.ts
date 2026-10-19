// Headless full-run simulator (PLAN.md §13): plays whole worlds with
// scripted bots against the real rules, scheduler and database, on a
// simulated clock, and reports how each run went.
//   DATABASE_URL=postgres://... npm run sim -- --players 2 --bots balanced --difficulty normal --runs 3
// Options: --players N (1–6), --bots kind[,kind…] (turtle, expander,
// balanced; cycled over the players), --difficulty story|normal|hard|nightmare,
// --runs N, --speed N (world speed), --days N (game days before giving up),
// --json (one JSON line per run).
import { parseArgs } from 'node:util';
import { createGuestAccount } from '../db/accounts.js';
import { findBridge } from '../db/bridges.js';
import { migrate } from '../db/migrate.js';
import { createPool, inTransaction, type Db } from '../db/pool.js';
import { getWorld } from '../db/worlds.js';
import { listVillages } from '../db/villages.js';
import { loadVault } from '../db/vaults.js';

const KINDS = ['wood', 'stone', 'grain', 'iron'] as const;
import { createWorldCommand, joinWorldCommand, startWorldCommand } from '../commands/worlds.js';
import { loadGameData, type Difficulty } from '../data/index.js';
import { handlers } from '../scheduler/handlers.js';
import { tick } from '../scheduler/worker.js';
import { BOT_KINDS, feedVault, playTurn, stats, terrainOf, type Bot, type BotKind } from './bots.js';

const MS_PER_HOUR = 3_600_000;

export interface RunResult {
  outcome: 'won' | 'lost' | 'unfinished';
  days: number;
  players: number;
  bots: BotKind[];
  difficulty: Difficulty;
  bridgeStage: number;
  bridgeQuestsOpen: string[];
  sanctity: number;
  ritualCalled: boolean;
  villages: number;
  villagesLost: number;
  wavesFaced: number;
  wavesBeaten: number;
  // The front whose horde last struck the Holy City (losses only).
  lastStruckBy: string | null;
  commands: number;
  refused: number;
}

export async function runOnce(
  db: Db,
  opts: { players: number; bots: BotKind[]; difficulty: Difficulty; speed: number; days: number; seed: number; verbose?: boolean },
): Promise<RunResult> {
  const deps = { data: loadGameData(), handlers };
  const start = new Date('2030-01-01T06:00:00Z');
  let now = start;
  stats.commands = 0;
  stats.refused = 0;
  stats.reasons = {};

  const bots: Bot[] = [];
  const accounts = [];
  for (let i = 0; i < opts.players; i++) {
    const name = `${opts.bots[i % opts.bots.length]}-${i + 1}`;
    const { account } = await inTransaction(db, (c) => createGuestAccount(c, name));
    accounts.push(account);
    bots.push({ accountId: account.id, name, kind: opts.bots[i % opts.bots.length]! });
  }
  const created = await createWorldCommand(db, {
    account: accounts[0]!,
    name: `sim ${opts.seed}`,
    maxPlayers: opts.players,
    speed: opts.speed,
    difficulty: opts.difficulty,
  });
  for (const account of accounts.slice(1)) await joinWorldCommand(db, { account, inviteCode: created.inviteCode! });
  const world = await startWorldCommand(db, deps, { account: accounts[0]!, worldId: created.id, now });
  const terrain = await terrainOf(db, world.id);

  // One bot turn per game hour.
  const step = MS_PER_HOUR / opts.speed;
  const end = start.getTime() + (opts.days * 24 * MS_PER_HOUR) / opts.speed;
  let status = world.status;
  while (now.getTime() < end) {
    now = new Date(now.getTime() + step);
    await tick(db, now, deps);
    status = (await inTransaction(db, (c) => getWorld(c, world.id))).status;
    if (status === 'won' || status === 'lost') break;
    const day = Math.floor(((now.getTime() - start.getTime()) * opts.speed) / (24 * MS_PER_HOUR));
    const ctx = { db, deps, world, terrain, now, day };
    if (opts.verbose && (now.getTime() - start.getTime()) % ((24 * MS_PER_HOUR) / opts.speed) < step) await progress(db, world.id, day);
    for (const bot of bots) {
      // A tithe for the bridge every six game hours, before anything else is spent.
      if (Math.floor(((now.getTime() - start.getTime()) * opts.speed) / MS_PER_HOUR) % 6 === 0) await feedVault(ctx, bot, 0.4);
      await playTurn(ctx, bot);
    }
  }
  return summarize(db, deps.data, world.id, opts, now, start, status);
}

// One line a game day: what each village has, and the bridge.
async function progress(db: Db, worldId: number, day: number): Promise<void> {
  await inTransaction(db, async (c) => {
    const world = await getWorld(c, worldId);
    const bridge = await findBridge(c, worldId);
    const villages = await listVillages(c, worldId);
    const parts = villages.map((v) => {
      const fighters = Object.entries(v.state.garrison).filter(([u]) => u !== 'scout' && u !== 'settler').reduce((n, [, k]) => n + k, 0);
      const fields = Object.values(v.state.plots).filter((p) => p.building && ['woodcutter', 'quarry', 'farm', 'iron_mine'].includes(p.building)).reduce((n, p) => n + p.level, 0);
      const stock = Object.values(v.state.ledger.amounts).map((n) => Math.round(n / 100)).join('/');
      const center = Object.entries(v.state.levels).filter(([b]) => !['woodcutter', 'quarry', 'farm', 'iron_mine', 'outpost'].includes(b)).map(([b, l]) => `${b.slice(0, 4)}${l}`).join(' ');
      return `${v.ruin ? 'RUIN ' : ''}fields ${fields} army ${fighters} q${v.state.queue.length} [${center}] stock ${stock}`;
    });
    const donated = KINDS.map((k) => Math.round((bridge?.donated[k] ?? 0) / 100)).join('/');
    const vault = (await loadVault(c, worldId)).amounts;
    console.log(
      `day ${day}: sanctity ${world.sanctity} embers ${world.embers} bridge ${bridge?.stage ?? 0}/${bridge?.status ?? '-'} given ${donated} vault ${KINDS.map((k) => Math.round(vault[k] / 100)).join('/')} quests ${Object.keys(bridge?.quests ?? {}).join(',')} | ${parts.join(' | ')}`,
    );
  });
}

async function summarize(
  db: Db,
  data: ReturnType<typeof loadGameData>,
  worldId: number,
  opts: { players: number; bots: BotKind[]; difficulty: Difficulty; speed: number },
  now: Date,
  start: Date,
  status: string,
): Promise<RunResult> {
  return inTransaction(db, async (c) => {
    const world = await getWorld(c, worldId);
    const bridge = await findBridge(c, worldId);
    const stage = bridge && bridge.status !== 'complete' ? data.bridge.stages[bridge.stage] : undefined;
    const count = async (sql: string) => (await c.query<{ n: number }>(sql, [worldId])).rows[0]!.n;
    const struck = await c.query<{ front: string }>(
      `SELECT w.front FROM battles b JOIN waves w ON w.id = b.wave_id
       WHERE b.world_id = $1 AND b.village_id IS NULL AND b.status = 'raided' ORDER BY b.id DESC LIMIT 1`,
      [worldId],
    );
    return {
      outcome: status === 'won' ? 'won' : status === 'lost' ? 'lost' : 'unfinished',
      days: Math.round((((now.getTime() - start.getTime()) * opts.speed) / (24 * MS_PER_HOUR)) * 10) / 10,
      players: opts.players,
      bots: opts.bots,
      difficulty: opts.difficulty,
      bridgeStage: bridge ? (bridge.status === 'complete' ? data.bridge.stages.length : bridge.stage) : 0,
      bridgeQuestsOpen: stage ? stage.quests.map((q) => q.kind).filter((k) => !bridge!.quests[k]) : [],
      sanctity: world.sanctity,
      ritualCalled: world.ritualAt !== null,
      villages: await count('SELECT count(*)::int AS n FROM villages WHERE world_id = $1 AND ruin IS NULL AND NOT refuge'),
      villagesLost: await count('SELECT count(*)::int AS n FROM villages WHERE world_id = $1 AND ruin IS NOT NULL'),
      wavesFaced: await count('SELECT count(*)::int AS n FROM waves WHERE world_id = $1 AND spawn_q IS NOT NULL'),
      wavesBeaten: await count("SELECT count(*)::int AS n FROM waves WHERE world_id = $1 AND status = 'defeated'"),
      lastStruckBy: struck.rows[0]?.front ?? null,
      commands: stats.commands,
      refused: stats.refused,
    };
  });
}

function line(r: RunResult): string {
  const how = r.outcome === 'lost' ? `lost on day ${r.days} (last struck by the ${r.lastStruckBy ?? '?'} front)` : r.outcome === 'won' ? `won on day ${r.days}` : `unfinished after ${r.days} days`;
  return (
    `${how} · bridge ${r.bridgeStage}/5${r.bridgeQuestsOpen.length ? ` (waiting on ${r.bridgeQuestsOpen.join(', ')})` : ''}` +
    `${r.ritualCalled ? ' · Ritual Night called' : ''} · sanctity ${r.sanctity} · villages ${r.villages} (${r.villagesLost} lost)` +
    ` · waves ${r.wavesBeaten}/${r.wavesFaced} beaten · ${r.commands} orders, ${r.refused} refused`
  );
}

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: {
      players: { type: 'string', default: '2' },
      bots: { type: 'string', default: 'balanced' },
      difficulty: { type: 'string', default: 'normal' },
      runs: { type: 'string', default: '1' },
      speed: { type: 'string', default: '20' },
      days: { type: 'string', default: '45' },
      json: { type: 'boolean', default: false },
      verbose: { type: 'boolean', default: false },
    },
  });
  const bots = values.bots.split(',').map((b) => b.trim()) as BotKind[];
  for (const b of bots) if (!BOT_KINDS.includes(b)) throw new Error(`Unknown bot "${b}" (${BOT_KINDS.join(', ')})`);
  const db = createPool();
  await migrate(db);
  const results: RunResult[] = [];
  for (let i = 0; i < Number(values.runs); i++) {
    const result = await runOnce(db, {
      players: Number(values.players),
      bots,
      difficulty: values.difficulty as Difficulty,
      speed: Number(values.speed),
      days: Number(values.days),
      seed: i,
      verbose: values.verbose,
    });
    results.push(result);
    console.log(values.json ? JSON.stringify(result) : `run ${i + 1}: ${line(result)}`);
    if (values.verbose) console.log(Object.entries(stats.reasons).sort((a, b) => b[1] - a[1]).slice(0, 12).map(([r, n]) => `  ${n} × ${r}`).join('\n'));
  }
  const won = results.filter((r) => r.outcome === 'won').length;
  if (!values.json) console.log(`${won}/${results.length} won (${values.players} players, ${values.bots}, ${values.difficulty})`);
  await db.end();
}

if (import.meta.url === `file://${process.argv[1]}`) await main();
