// End-to-end smoke run of the M0 scheduler: creates a fast world, queues
// builds through the command path and lets a worker loop finish them.
//   DATABASE_URL=postgres://... npm run demo
import { queueBuildCommand } from './commands/queue-build.js';
import { loadGameData } from './data/index.js';
import { migrate } from './db/migrate.js';
import { createPool, inTransaction } from './db/pool.js';
import { createGuestAccount } from './db/accounts.js';
import { insertVillage, loadVillage } from './db/villages.js';
import { createWorld } from './db/worlds.js';
import { handlers } from './scheduler/handlers.js';
import { tick } from './scheduler/worker.js';
import { amountsAt, RESOURCE_KINDS } from './sim/resources.js';
import { newVillage } from './sim/village.js';

const SPEED = 100;

const db = createPool();
await migrate(db);
const deps = { data: loadGameData(), handlers };

const { villageId, accountId } = await inTransaction(db, async (client) => {
  const { account } = await createGuestAccount(client, 'Demo player');
  const world = await createWorld(client, { name: 'Demo', seed: Date.now(), speed: SPEED });
  const village = await insertVillage(client, {
    worldId: world.id,
    ownerAccountId: account.id,
    name: 'Demo village',
    q: 2,
    r: 0,
    state: newVillage(deps.data, new Date(), world.speed),
  });
  return { villageId: village.id, accountId: account.id };
});

async function report(label: string): Promise<void> {
  const village = await inTransaction(db, (client) => loadVillage(client, villageId));
  const amounts = amountsAt(village.state.ledger, new Date());
  const fmt = RESOURCE_KINDS.map((k) => `${k} ${Math.floor(amounts[k])}`).join(', ');
  console.log(`${label.padEnd(24)} levels ${JSON.stringify(village.state.levels)} | ${fmt} | queue ${village.state.queue.length}`);
}

await report('start');
for (const building of ['woodcutter', 'farm']) {
  const { queued } = await queueBuildCommand(db, deps, { accountId, villageId, building, now: new Date() });
  console.log(`queued ${building} -> level ${queued.targetLevel}, done at ${queued.completesAt.toISOString()}`);
}
await report('after queueing');

const deadline = Date.now() + 10_000;
for (;;) {
  const result = await tick(db, new Date(), deps);
  if (result.events > 0) await report(`tick: ${result.events} event(s)`);
  const village = await inTransaction(db, (client) => loadVillage(client, villageId));
  if (village.state.queue.length === 0 || Date.now() > deadline) break;
  await new Promise((resolve) => setTimeout(resolve, 100));
}
await report('end');
await db.end();
