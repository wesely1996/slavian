// Many simulator runs at once (PLAN.md M5 step 27): every player count and
// preset asked for, several runs each on fixed map seeds (so two tunings
// meet the same maps), spread over parallel processes, then a table of
// win rates.
//   DATABASE_URL=postgres://... npm run sim:matrix -- --players 1,2,4 --difficulty normal --runs 8 --jobs 4
// Options as for `npm run sim` (--bots, --speed, --days), plus --jobs N
// (processes at once) and --json (every run, one JSON line each, with the
// table on stderr).
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import type { RunResult } from './run.js';

interface Job {
  players: number;
  difficulty: string;
  seed: number;
}

const RUN = fileURLToPath(new URL('./run.ts', import.meta.url));

function play(job: Job, opts: { bots: string; speed: string; days: string }): Promise<RunResult> {
  return new Promise((resolve, reject) => {
    const args = ['--import', 'tsx', RUN, '--json', '--runs', '1', '--players', String(job.players), '--difficulty', job.difficulty,
      '--seed', String(job.seed), '--bots', opts.bots, '--speed', opts.speed, '--days', opts.days];
    const child = spawn(process.execPath, args, { stdio: ['ignore', 'pipe', 'inherit'] });
    let out = '';
    child.stdout.on('data', (chunk: Buffer) => (out += chunk.toString()));
    child.on('close', (code) => {
      const line = out.trim().split('\n').filter((l) => l.startsWith('{')).pop();
      if (code !== 0 || !line) reject(new Error(`run ${JSON.stringify(job)} failed (${code})`));
      else resolve(JSON.parse(line) as RunResult);
    });
  });
}

// The middle value of a sorted copy.
function median(values: number[]): number {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted.length ? sorted[Math.floor(sorted.length / 2)]! : 0;
}

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: {
      players: { type: 'string', default: '1,2,3,4' },
      difficulty: { type: 'string', default: 'normal' },
      bots: { type: 'string', default: 'balanced' },
      runs: { type: 'string', default: '6' },
      jobs: { type: 'string', default: '4' },
      speed: { type: 'string', default: '20' },
      days: { type: 'string', default: '70' },
      json: { type: 'boolean', default: false },
    },
  });
  const jobs: Job[] = [];
  for (const difficulty of values.difficulty.split(','))
    for (const players of values.players.split(',').map(Number))
      for (let seed = 1; seed <= Number(values.runs); seed++) jobs.push({ players, difficulty, seed });

  const results = new Map<string, RunResult[]>();
  let next = 0;
  const worker = async () => {
    while (next < jobs.length) {
      const job = jobs[next++]!;
      const result = await play(job, values);
      if (values.json) console.log(JSON.stringify({ seed: job.seed, ...result }));
      const key = `${job.difficulty} ${job.players}`;
      results.set(key, [...(results.get(key) ?? []), result]);
    }
  };
  await Promise.all(Array.from({ length: Number(values.jobs) }, worker));
  const log = values.json ? console.error : console.log;

  log(`bots ${values.bots}, ${values.runs} runs each, up to ${values.days} days`);
  log('preset     players  won    lost (fronts)                  unfinished  days won  bridge  villages lost');
  for (const difficulty of values.difficulty.split(','))
    for (const players of values.players.split(',').map(Number)) {
      const runs = results.get(`${difficulty} ${players}`) ?? [];
      const won = runs.filter((r) => r.outcome === 'won');
      const lost = runs.filter((r) => r.outcome === 'lost');
      const fronts = lost.map((r) => r.lastStruckBy ?? '?').join(',');
      const unfinished = runs.filter((r) => r.outcome === 'unfinished').length;
      const pct = runs.length ? Math.round((won.length / runs.length) * 100) : 0;
      log(
        `${difficulty.padEnd(10)} ${String(players).padEnd(8)} ${`${won.length}/${runs.length} ${pct}%`.padEnd(6)} ` +
          `${`${lost.length} (${fronts})`.padEnd(30)} ${String(unfinished).padEnd(11)} ${String(median(won.map((r) => r.days))).padEnd(9)} ` +
          `${String(median(runs.map((r) => r.bridgeStage))).padEnd(7)} ${median(runs.map((r) => r.villagesLost))}`,
      );
    }
}

await main();
