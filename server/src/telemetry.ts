// Prints the telemetry of the last N days (default 30) as JSON, for
// balancing: `npm run telemetry -- 7` (DATABASE_URL as for the server).
import { inTransaction, createPool } from './db/pool.js';
import { telemetrySummary } from './db/telemetry.js';

const days = Number(process.argv[2] ?? 30);
const db = createPool();
const since = new Date(Date.now() - days * 86_400_000);
const summary = await inTransaction(db, (client) => telemetrySummary(client, since));
console.log(JSON.stringify({ days, ...summary }, null, 2));
await db.end();
