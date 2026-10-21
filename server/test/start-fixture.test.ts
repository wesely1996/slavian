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

const FIXTURE = fileURLToPath(new URL('../../data/fixtures/start-world.json', import.meta.url));
const scheduler = { data: loadGameData(), handlers };
export const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Solo', displayName: 'You', speed: 1, difficulty: 'normal' };

// Replaces the server's ids with the local engine's, recursively, by key.
function localIds(view: Record<string, unknown>): unknown {
  const ids = {
    world: new Map([[view.id as number, -1]]),
    account: new Map<number, number>(),
    village: new Map<number, number>(),
    wave: new Map<number, number>(),
    site: new Map<number, number>(),
  };
  for (const [i, m] of (view.members as { accountId: number }[]).entries()) ids.account.set(m.accountId, i + 1);
  for (const [i, v] of (view.villages as { id: number }[]).entries()) ids.village.set(v.id, i + 1);
  for (const [i, w] of (view.waves as { id: number }[]).entries()) ids.wave.set(w.id, i + 1);
  for (const [i, s] of (view.sites as { id: number }[]).entries()) ids.site.set(s.id, i + 1);
  const keyed: Record<string, Map<number, number>> = {
    worldId: ids.world,
    accountId: ids.account, ownerAccountId: ids.account, hostAccountId: ids.account, exploredBy: ids.account,
    villageId: ids.village, homeVillageId: ids.village, targetVillageId: ids.village,
    waveId: ids.wave,
    siteId: ids.site,
  };
  const walk = (node: unknown, parent: string | null): unknown => {
    if (Array.isArray(node)) return node.map((x) => walk(x, parent));
    if (node && typeof node === 'object') {
      const out: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(node)) {
        if (k === 'id' && typeof v === 'number' && parent && ids[parent as keyof typeof ids]) out[k] = ids[parent as keyof typeof ids].get(v) ?? v;
        else if (typeof v === 'number' && keyed[k]) out[k] = keyed[k].get(v) ?? v;
        else out[k] = walk(v, k === 'villages' ? 'village' : k === 'waves' ? 'wave' : k === 'sites' ? 'site' : k === 'members' ? 'account' : null);
      }
      return out;
    }
    return node;
  };
  const out = walk(view, 'world') as Record<string, unknown>;
  // A solo world on the device has no invite code.
  out.inviteCode = null;
  return out;
}

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
    const view = localIds(await call('GET', `/v1/worlds/${world.id}`, token));
    if (process.env.UPDATE_FIXTURES) writeFileSync(FIXTURE, JSON.stringify(view, null, 1) + '\n');
    expect(view).toEqual(JSON.parse(readFileSync(FIXTURE, 'utf8')));
  });
});
