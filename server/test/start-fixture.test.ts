// The local engine's golden fixture (docs/local-engine.md): a solo world
// started on the real server with a fixed seed and clock, its world view
// with the database's ids replaced by the local engine's (world -1, the
// player 1, villages, waves and sites numbered from 1 in order). The client
// test starts the same world in the app and must produce the same view.
// UPDATE_FIXTURES=1 rewrites it after a rule change.
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/api/app.js';
import { loadGameData } from '../src/data/index.js';
import type { Db } from '../src/db/pool.js';
import { handlers } from '../src/scheduler/handlers.js';
import { createTestDb, TEST_DATABASE_URL } from './db.js';
import { idMapsFrom, toLocalIds } from './local-ids.js';

const FIXTURE = fileURLToPath(new URL('../../data/fixtures/start-world.json', import.meta.url));
const scheduler = { data: loadGameData(), handlers };
export const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Solo', displayName: 'You', speed: 1, difficulty: 'normal' };

describe.skipIf(!TEST_DATABASE_URL)('start-world fixture for the local engine (postgres)', () => {
  let db: Db;
  let cleanup: () => Promise<void>;
  const now = new Date(START.at);
  let app: Awaited<ReturnType<typeof buildApp>>;
  beforeAll(async () => {
    ({ db, cleanup } = await createTestDb());
    app = await buildApp({ db, scheduler, clock: () => now });
  });
  afterAll(async () => {
    await app?.close();
    await cleanup?.();
  });

  it('matches a solo world started on the server', async () => {
    const call = async (method: string, url: string, token?: string, body?: unknown) =>
      (await app.inject({ method: method as 'GET', url, headers: token ? { authorization: `Bearer ${token}` } : {}, ...(body === undefined ? {} : { payload: body as object }) })).json();
    const { token } = await call('POST', '/v1/auth/guest', undefined, { displayName: START.displayName });
    const world = await call('POST', '/v1/worlds', token, { name: START.name, maxPlayers: 1, speed: START.speed, difficulty: START.difficulty });
    await db.query('UPDATE worlds SET seed = $2 WHERE id = $1', [world.id, START.seed]);
    await call('POST', `/v1/worlds/${world.id}/start`, token);
    const raw = await call('GET', `/v1/worlds/${world.id}`, token);
    const view = toLocalIds(raw, idMapsFrom(raw));
    if (process.env.UPDATE_FIXTURES) writeFileSync(FIXTURE, JSON.stringify(view, null, 1) + '\n');
    expect(view).toEqual(JSON.parse(readFileSync(FIXTURE, 'utf8')));
  });
});
