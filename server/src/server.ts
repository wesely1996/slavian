// Game server: HTTP + WebSocket API, plus an inline scheduler worker so a
// single process is enough on a small VPS (set INLINE_WORKER=0 to run
// workers separately with `npm run worker`).
import { buildApp } from './api/app.js';
import { LiveHub } from './api/live.js';
import { loadGameData } from './data/index.js';
import { migrate } from './db/migrate.js';
import { createPool, pooledEndpointWarning } from './db/pool.js';
import { upgradeHeroes, upgradeLegacyVillages } from './db/upgrades.js';
import { handlers } from './scheduler/handlers.js';
import { runWorkerLoop } from './scheduler/loop.js';

const port = Number(process.env.PORT ?? 8080);
const host = process.env.HOST ?? '0.0.0.0';

const warning = process.env.DATABASE_URL ? pooledEndpointWarning(process.env.DATABASE_URL) : null;
if (warning) console.warn(`WARNING: ${warning}`);
const db = createPool();
const applied = await migrate(db);
if (applied.length) console.log(`Applied migrations: ${applied.join(', ')}`);

const scheduler = { data: loadGameData(), handlers };
const upgraded = await upgradeLegacyVillages(db, scheduler.data);
if (upgraded) console.log(`Laid out ${upgraded} older village(s) on plots`);
const heroes = await upgradeHeroes(db, scheduler.data);
if (heroes) console.log(`Gave ${heroes} player(s) in older worlds a hero`);
const clock = () => new Date();
const live = new LiveHub(db, scheduler.data, clock);
await live.start();
const app = await buildApp({ db, scheduler, clock, live, logger: true });
await app.listen({ port, host });

const abort = new AbortController();
const worker =
  process.env.INLINE_WORKER === '0'
    ? Promise.resolve()
    : runWorkerLoop(db, scheduler, { pollMs: Number(process.env.WORKER_POLL_MS ?? 500), signal: abort.signal });

async function shutdown(): Promise<void> {
  abort.abort();
  await app.close();
  await live.stop();
  await worker;
  await db.end();
}
for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.once(signal, () => {
    shutdown().then(
      () => process.exit(0),
      (error) => {
        console.error(error);
        process.exit(1);
      },
    );
  });
}
