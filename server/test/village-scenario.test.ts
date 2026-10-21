// A scripted solo session recorded on the real server for the local engine
// (docs/local-engine.md): every request's answer, with the local engine's
// ids, and the clock moved on between them. The client test replays the
// script against a solo world started in the app and must get the same
// answers. UPDATE_FIXTURES=1 rewrites it after a rule change.
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/api/app.js';
import { loadGameData } from '../src/data/index.js';
import type { Db } from '../src/db/pool.js';
import { handlers } from '../src/scheduler/handlers.js';
import { tick } from '../src/scheduler/worker.js';
import { hexDistance, neighbors, hex } from '../src/sim/hex.js';
import { createTestDb, TEST_DATABASE_URL } from './db.js';
import { idMapsFrom, toLocalIds, type LocalIdMaps } from './local-ids.js';

const FIXTURE = fileURLToPath(new URL('../../data/fixtures/village-scenario.json', import.meta.url));
const scheduler = { data: loadGameData(), handlers };
const START = { seed: 777, at: '2026-06-01T08:00:00.000Z', name: 'Villages', displayName: 'You', speed: 10, difficulty: 'normal' };
const MINUTE = 60_000;

// Requests use the local engine's ids ("/v1/villages/1/build"); `advance`
// moves the clock on and runs what fell due.
type Step = { advance?: number; method?: string; path?: string; body?: unknown };

describe.skipIf(!TEST_DATABASE_URL)('village scenario for the local engine (postgres)', () => {
  let db: Db;
  let cleanup: () => Promise<void>;
  let now = new Date(START.at);
  let app: Awaited<ReturnType<typeof buildApp>>;
  beforeAll(async () => {
    ({ db, cleanup } = await createTestDb());
    app = await buildApp({ db, scheduler, clock: () => now });
  });
  afterAll(async () => {
    await app?.close();
    await cleanup?.();
  });

  it('answers as recorded', async () => {
    const call = async (method: string, url: string, token?: string, body?: unknown) => {
      const res = await app.inject({ method: method as 'GET', url, headers: token ? { authorization: `Bearer ${token}` } : {}, ...(body === undefined ? {} : { payload: body as object }) });
      return { status: res.statusCode, body: res.json() };
    };
    const { token } = (await call('POST', '/v1/auth/guest', undefined, { displayName: START.displayName })).body;
    const world = (await call('POST', '/v1/worlds', token, { name: START.name, maxPlayers: 1, speed: START.speed, difficulty: START.difficulty })).body;
    await db.query('UPDATE worlds SET seed = $2 WHERE id = $1', [world.id, START.seed]);
    await call('POST', `/v1/worlds/${world.id}/start`, token);
    const started = (await call('GET', `/v1/worlds/${world.id}`, token)).body;
    const maps: LocalIdMaps = idMapsFrom(started);
    const realVillage = [...maps.village.keys()][0]!;
    // An outpost hex: the first neighbour of the village (in hex order)
    // with something to gather and no site on it.
    const home = started.villages[0];
    const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
    const yields = scheduler.data.buildings.buildings.outpost!.yields ?? {};
    const outpost = neighbors(hex(home.q, home.r)).find((n) => yields[terrain.get(`${n.q},${n.r}`) as keyof typeof yields] && !started.sites.some((s: { q: number; r: number }) => s.q === n.q && s.r === n.r) && hexDistance(n, hex(0, 0)) > 0)!;

    const steps: Step[] = [
      { method: 'POST', path: '/v1/villages/1/build', body: { plot: 'f6' } },
      { method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'barracks' } },
      { method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c3', building: 'storehouse' } },
      { method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 5 } },
      { advance: 30 * MINUTE },
      { method: 'GET', path: '/v1/worlds/-1' },
      { method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c3', building: 'barracks' } },
      { method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 5 } },
      { method: 'POST', path: '/v1/villages/1/stance', body: { stance: 'defensive' } },
      { method: 'POST', path: '/v1/villages/1/outposts', body: { q: outpost.q, r: outpost.r } },
      { method: 'POST', path: '/v1/villages/1/outposts', body: { q: home.q, r: home.r } },
      { advance: 7 * MINUTE },
      { method: 'POST', path: '/v1/villages/1/build', body: { building: 'farm' } },
      { method: 'POST', path: '/v1/villages/1/rename', body: { name: 'Kitezh' } },
      { advance: 120 * MINUTE },
      { method: 'POST', path: '/v1/worlds/-1/onboarding/claim', body: { step: 'build' } },
      { method: 'POST', path: '/v1/worlds/-1/onboarding/claim', body: { step: 'scout' } },
      { method: 'POST', path: '/v1/villages/1/outposts', body: { q: outpost.q, r: outpost.r } },
      { method: 'POST', path: '/v1/villages/1/outposts/abandon', body: { q: outpost.q, r: outpost.r } },
      { advance: 60 * MINUTE },
      { method: 'POST', path: '/v1/worlds/-1/onboarding/claim', body: { step: 'outpost' } },
      { method: 'GET', path: '/v1/worlds/-1' },
      { method: 'POST', path: '/v1/villages/1/outposts/abandon', body: { q: outpost.q, r: outpost.r } },
      { method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 50 } },
      { advance: 45 * MINUTE + 17_000 },
      { method: 'GET', path: '/v1/worlds/-1' },
    ];
    const recorded: unknown[] = [];
    for (const step of steps) {
      if (step.advance) {
        now = new Date(now.getTime() + step.advance);
        await tick(db, now, scheduler);
        recorded.push({ advance: step.advance });
        continue;
      }
      const real = step.path!.replace('/v1/villages/1/', `/v1/villages/${realVillage}/`).replace('/v1/worlds/-1', `/v1/worlds/${world.id}`);
      const answer = await call(step.method!, real, token, step.body);
      recorded.push({ ...step, status: answer.status, response: toLocalIds(answer.body, maps) });
    }
    const fixture = { start: START, steps: recorded };
    if (process.env.UPDATE_FIXTURES) writeFileSync(FIXTURE, JSON.stringify(fixture, null, 1) + '\n');
    expect(fixture).toEqual(JSON.parse(readFileSync(FIXTURE, 'utf8')));
  });
});
