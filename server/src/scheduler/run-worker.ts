// Standalone scheduler worker, for running workers separately from the API.
import { loadGameData } from '../data/index.js';
import { createPool } from '../db/pool.js';
import { handlers } from './handlers.js';
import { runWorkerLoop } from './loop.js';

const db = createPool();
const abort = new AbortController();
for (const signal of ['SIGINT', 'SIGTERM'] as const) process.on(signal, () => abort.abort());

console.log('Scheduler worker started');
await runWorkerLoop(db, { data: loadGameData(), handlers }, {
  pollMs: Number(process.env.WORKER_POLL_MS ?? 500),
  signal: abort.signal,
});
await db.end();
console.log('Scheduler worker stopped');
