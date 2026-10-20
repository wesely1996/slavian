// Game server: HTTP + WebSocket API, plus an inline scheduler worker so a
// single process is enough on a small VPS (set INLINE_WORKER=0 to run
// workers separately with `npm run worker`).
import { buildApp } from './api/app.js';
import { LiveHub } from './api/live.js';
import { loadGameData } from './data/index.js';
import { migrate } from './db/migrate.js';
import { createPool, pooledEndpointWarning } from './db/pool.js';
import { upgradeDigests, upgradeHeroes, upgradeLegacyVillages, upgradeSites, upgradeTownNames, upgradeWallPlots } from './db/upgrades.js';
import { pushSenderFromEnv } from './push/sender.js';
import { runPushLoop } from './push/worker.js';
import { handlers } from './scheduler/handlers.js';
import { runWorkerLoop } from './scheduler/loop.js';
import { alert } from './alerts.js';

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
const walled = await upgradeWallPlots(db, scheduler.data);
if (walled) console.log(`Gave ${walled} older village(s) room for walls`);
const heroes = await upgradeHeroes(db, scheduler.data);
if (heroes) console.log(`Gave ${heroes} player(s) in older worlds a hero`);
await upgradeDigests(db, new Date());
const named = await upgradeTownNames(db, scheduler.data);
if (named) console.log(`Named ${named} town(s) given the old default names`);
const sited = await upgradeSites(db, scheduler.data);
if (sited) console.log(`Placed ancient sites in ${sited} running world(s)`);
// A crash is reported before the process goes down (Docker restarts it).
process.on('uncaughtExceptionMonitor', (error) => void alert('crash', `Server crashed: ${error.message}`));
if (process.env.ALERT_WEBHOOK_URL) console.log('Alerts: on (ALERT_WEBHOOK_URL)');
const pushSender = pushSenderFromEnv();
console.log(pushSender ? 'Push notifications: Firebase Cloud Messaging' : 'Push notifications: off (no FCM service account); in-app inbox only');
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
const pusher = runPushLoop(db, scheduler.data, pushSender, { pollMs: Number(process.env.PUSH_POLL_MS ?? 5000), signal: abort.signal });

async function shutdown(): Promise<void> {
  abort.abort();
  await app.close();
  await live.stop();
  await worker;
  await pusher;
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
