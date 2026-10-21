// Scripted solo sessions recorded on the real server for the local engine
// (docs/local-engine.md): every request's answer, with the local engine's
// ids, and the clock moved on between them. The client test replays each
// script against a solo world started in the app and must get the same
// answers. UPDATE_FIXTURES=1 rewrites a fixture after a rule change.
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/api/app.js';
import { loadGameData } from '../src/data/index.js';
import type { Db } from '../src/db/pool.js';
import { handlers } from '../src/scheduler/handlers.js';
import { tick } from '../src/scheduler/worker.js';
import { createTestDb, TEST_DATABASE_URL } from './db.js';
import { idMapsFrom, toLocalIds, type LocalIdMaps } from './local-ids.js';

export const MINUTE = 60_000;
export const scheduler = { data: loadGameData(), handlers };

export interface ScenarioStart {
  seed: number;
  at: string;
  name: string;
  displayName: string;
  speed: number;
  difficulty: string;
}

// Requests use the local engine's ids ("/v1/villages/1/build"); `advance`
// moves the clock on and runs what fell due; `set` jumps the world ahead
// where play would take too long (the bridge's state, the group's Ember),
// and the client test makes the same change.
export type WorldSet = { bridge?: Record<string, unknown>; embers?: number };
export type Step = { advance?: number; method?: string; path?: string; body?: unknown; set?: WorldSet };

export interface Session {
  // The world as it started (the server's ids).
  readonly started: Record<string, any>;
  readonly maps: LocalIdMaps;
  now(): Date;
  // Plays and records a step; a request's answer comes back with local ids.
  play(step: Step): Promise<{ status: number; body: any }>;
}

export function scenario(fixture: string, start: ScenarioStart, script: (session: Session) => Promise<void>): void {
  const path = fileURLToPath(new URL(`../../data/fixtures/${fixture}`, import.meta.url));
  describe.skipIf(!TEST_DATABASE_URL)(`${fixture} for the local engine (postgres)`, () => {
    let db: Db;
    let cleanup: () => Promise<void>;
    let now = new Date(start.at);
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
      const { token } = (await call('POST', '/v1/auth/guest', undefined, { displayName: start.displayName })).body;
      const world = (await call('POST', '/v1/worlds', token, { name: start.name, maxPlayers: 1, speed: start.speed, difficulty: start.difficulty })).body;
      await db.query('UPDATE worlds SET seed = $2 WHERE id = $1', [world.id, start.seed]);
      await call('POST', `/v1/worlds/${world.id}/start`, token);
      const started = (await call('GET', `/v1/worlds/${world.id}`, token)).body;
      const maps = idMapsFrom(started);
      const realVillage = [...maps.village.keys()][0]!;

      const recorded: unknown[] = [];
      await script({
        started,
        maps,
        now: () => now,
        async play(step) {
          if (step.set) {
            if (step.set.bridge) {
              await db.query(
                'INSERT INTO bridges (world_id, state) VALUES ($1, $2) ON CONFLICT (world_id) DO UPDATE SET state = EXCLUDED.state',
                [world.id, JSON.stringify(step.set.bridge)],
              );
            }
            if (step.set.embers !== undefined) await db.query('UPDATE worlds SET embers = $2 WHERE id = $1', [world.id, step.set.embers]);
            recorded.push({ set: step.set });
            return { status: 200, body: null };
          }
          if (step.advance) {
            now = new Date(now.getTime() + step.advance);
            await tick(db, now, scheduler);
            recorded.push({ advance: step.advance });
            return { status: 200, body: null };
          }
          const real = step.path!.replace('/v1/villages/1/', `/v1/villages/${realVillage}/`).replace('/v1/worlds/-1', `/v1/worlds/${world.id}`);
          const answer = await call(step.method!, real, token, step.body);
          const body = toLocalIds(answer.body, maps);
          recorded.push({ ...step, status: answer.status, response: body });
          return { status: answer.status, body };
        },
      });
      const fixture = { start, steps: recorded };
      if (process.env.UPDATE_FIXTURES) writeFileSync(path, JSON.stringify(fixture, null, 1) + '\n');
      expect(fixture).toEqual(JSON.parse(readFileSync(path, 'utf8')));
    });
  });
}
