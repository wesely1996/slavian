import { loadGameData } from '../data/index.js';
import { createPool } from '../db/pool.js';
import { handlers } from './handlers.js';
import { tick } from './worker.js';

const POLL_MS = Number(process.env.WORKER_POLL_MS ?? 500);

const db = createPool();
const deps = { data: loadGameData(), handlers };
let running = true;

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, () => {
    running = false;
  });
}

console.log(`Scheduler worker started (poll ${POLL_MS} ms)`);
while (running) {
  try {
    const result = await tick(db, new Date(), deps);
    if (result.events > 0 || result.skipped > 0) console.log(result);
  } catch (error) {
    console.error('Tick failed:', error);
  }
  await new Promise((resolve) => setTimeout(resolve, POLL_MS));
}
await db.end();
console.log('Scheduler worker stopped');
