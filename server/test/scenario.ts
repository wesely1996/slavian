// Scripted solo sessions recorded on the real server for the local engine
// (docs/local-engine.md): every request's answer, with the local engine's
// ids, and the clock moved on between them. The client test replays each
// script against a solo world started in the app and must get the same
// answers. UPDATE_FIXTURES=1 rewrites a fixture after a rule change.
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/api/app.js';
import { insertRivers } from '../src/db/rivers.js';
import { edgeKey } from '../src/sim/land.js';
import { startRitual } from '../src/scheduler/cultists.js';
import { raiseMountainCity } from '../src/scheduler/mapEvents.js';
import { interceptAt } from '../src/scheduler/field.js';
import { createCamp } from '../src/scheduler/camps.js';
import { leshenRises, leshenSeed } from '../src/scheduler/leshen.js';
import { getWorld } from '../src/db/worlds.js';
import type { Front } from '../src/sim/mapgen.js';
import type { TerrainId } from '../src/data/index.js';
import { loadGameData } from '../src/data/index.js';
import type { Db } from '../src/db/pool.js';
import { handlers } from '../src/scheduler/handlers.js';
import { tick } from '../src/scheduler/worker.js';
import { levelsOf } from '../src/sim/village.js';
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
// where play would take too long (the bridge's state, the group's Ember,
// the vault's stock, a horde's hatred), and the client test makes the same
// change.
export type WorldSet = {
  bridge?: Record<string, unknown>;
  embers?: number;
  vault?: Record<string, number>;
  // A front's hatred.
  frontHatred?: { front: string; hatred: number };
  // Cultists of Černobog begin their ritual at a hex (events.json ritual),
  // as the rare daily event would.
  ritual?: { q: number; r: number; front: string; guards: Record<string, number> };
  // Masons would raise a mountain city at a mountain hex (events.json
  // mountain_city), as the rare daily event would; `raiders` strike it.
  mountainCity?: { q: number; r: number; front: string; raiders: Record<string, number> };
  // A bandit camp or lair rises at a hex (camps.json), as one would after a wave.
  camp?: { q: number; r: number; kind: 'bandit' | 'lair'; front: string; units: Record<string, number> };
  // A fort's buildings (forts.json plots), grain and defenders, by id; as
  // a muster would, newly manned it stands in the way of hordes on the march.
  fort?: { id: number; plots: Record<string, { kind: string; level: number }>; grain: number; defenders?: Record<string, number> };
  // A river runs along the edge between two hexes (as the map would lay it).
  river?: { a: { q: number; r: number }; b: { q: number; r: number } };
  // The Leshen rises there now, as if a fire had woken him (events.json leshen).
  leshen?: { q: number; r: number };
  // Rivers the players dug already, along these edges (field.json terraform river).
  dugRivers?: { a: { q: number; r: number }; b: { q: number; r: number } }[];
  // Roads standing already (level 1), along these edges, built by the
  // player's (first) village.
  roads?: { a: { q: number; r: number }; b: { q: number; r: number } }[];
  // What the player has forged already (smithing.json), by unit and line.
  smithing?: Record<string, Record<string, number>>;
  // Units standing in the player's (first) village, by unit (their upkeep
  // counts from the village's next change).
  garrison?: Record<string, number>;
  // The player's (first) village's stores, as of its last settling.
  amounts?: Record<string, number>;
  // Units the player has bought that grow dearer (units.json costStep).
  bought?: Record<string, number>;
  // Buildings standing in the player's (first) village, by plot (its levels
  // follow; its rates and stores only from its next change).
  plots?: Record<string, { building: string; level: number; terrain?: TerrainId }>;
  // Techs the group knows already (in this order), and the research the
  // player's Academies have brought in (as of now).
  known?: string[];
  researchPoints?: number;
};
export type Step = { advance?: number; method?: string; path?: string; body?: unknown; set?: WorldSet };

export interface Session {
  // The world as it started (the server's ids).
  readonly started: Record<string, any>;
  readonly maps: LocalIdMaps;
  now(): Date;
  // Plays and records a step; a request's answer comes back with local ids.
  play(step: Step): Promise<{ status: number; body: any }>;
}

// `timeoutMs`: for a long script (the default is vitest's 5 s).
export function scenario(fixture: string, start: ScenarioStart, script: (session: Session) => Promise<void>, timeoutMs?: number): void {
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
            if (step.set.embers !== undefined) await db.query('UPDATE world_members SET embers = $2 WHERE world_id = $1', [world.id, step.set.embers]);
            if (step.set.vault) {
              await db.query('INSERT INTO vaults (world_id) VALUES ($1) ON CONFLICT DO NOTHING', [world.id]);
              await db.query('UPDATE vaults SET amounts = $2 WHERE world_id = $1', [world.id, JSON.stringify(step.set.vault)]);
            }
            if (step.set.ritual) {
              const r = step.set.ritual;
              const client = await db.connect();
              try {
                await startRitual(client, scheduler.data, await getWorld(client, world.id), { cell: { q: r.q, r: r.r }, front: r.front as Front, guards: r.guards }, now);
              } finally {
                client.release();
              }
            }
            if (step.set.mountainCity) {
              const m = step.set.mountainCity;
              const client = await db.connect();
              try {
                await raiseMountainCity(client, scheduler.data, await getWorld(client, world.id), { cell: { q: m.q, r: m.r }, front: m.front as Front, raiders: m.raiders }, now);
              } finally {
                client.release();
              }
            }
            if (step.set.camp) {
              const c = step.set.camp;
              const client = await db.connect();
              try {
                await createCamp(client, scheduler.data, await getWorld(client, world.id), { kind: c.kind, front: c.front as Front, q: c.q, r: c.r, units: c.units, waveId: null }, now);
              } finally {
                client.release();
              }
            }
            if (step.set.fort) {
              const f = step.set.fort;
              const { rows } = await db.query<{ q: number; r: number }>('UPDATE forts SET plots = $2, grain = $3, defenders = $4 WHERE id = $1 RETURNING q, r', [
                f.id,
                JSON.stringify(f.plots),
                f.grain,
                JSON.stringify(f.defenders ?? {}),
              ]);
              if (f.defenders && rows[0]) {
                const client = await db.connect();
                try {
                  await interceptAt(client, scheduler.data, await getWorld(client, world.id), { q: rows[0].q, r: rows[0].r }, now);
                } finally {
                  client.release();
                }
              }
            }
            if (step.set.leshen) {
              const client = await db.connect();
              try {
                const w = await getWorld(client, world.id);
                const cell = { q: step.set.leshen.q, r: step.set.leshen.r };
                await leshenRises(client, scheduler.data, w, cell, now, leshenSeed(w, cell, now));
              } finally {
                client.release();
              }
            }
            if (step.set.river) {
              const client = await db.connect();
              try {
                await insertRivers(client, world.id, [{ a: step.set.river.a, b: step.set.river.b, bridge: false, size: 1 }]);
              } finally {
                client.release();
              }
            }
            if (step.set.frontHatred) {
              await db.query('UPDATE worlds SET hatred = hatred || jsonb_build_object($2::text, $3::double precision) WHERE id = $1', [world.id, step.set.frontHatred.front, step.set.frontHatred.hatred]);
            }
            if (step.set.garrison) {
              await db.query(
                'UPDATE villages SET garrison = garrison || $2::jsonb WHERE id = (SELECT min(id) FROM villages WHERE world_id = $1)',
                [world.id, JSON.stringify(step.set.garrison)],
              );
            }
            if (step.set.dugRivers) {
              const client = await db.connect();
              try {
                await insertRivers(client, world.id, step.set.dugRivers.map((e) => ({ a: e.a, b: e.b, bridge: false, size: 1 })), true);
              } finally {
                client.release();
              }
            }
            for (const e of step.set.roads ?? []) {
              const [p, q] = edgeKey(e.a, e.b).startsWith(`${e.a.q},${e.a.r}|`) ? [e.a, e.b] : [e.b, e.a];
              await db.query(
                `INSERT INTO road_edges (world_id, aq, ar, bq, br, status, level, built_by, completes_at)
                 SELECT $1, $2, $3, $4, $5, 'standing', 1, id, NULL FROM villages WHERE id = (SELECT min(id) FROM villages WHERE world_id = $1)`,
                [world.id, p!.q, p!.r, q!.q, q!.r],
              );
            }
            if (step.set.smithing) {
              await db.query('UPDATE world_members SET smithing = $2 WHERE world_id = $1', [world.id, JSON.stringify(step.set.smithing)]);
            }
            if (step.set.bought) {
              await db.query('UPDATE world_members SET bought = bought || $2::jsonb WHERE world_id = $1', [world.id, JSON.stringify(step.set.bought)]);
            }
            if (step.set.plots) {
              const { rows } = await db.query<{ id: number; plots: Record<string, { building: string | null; level: number }> }>(
                'SELECT id, plots FROM villages WHERE id = (SELECT min(id) FROM villages WHERE world_id = $1)',
                [world.id],
              );
              const plots = { ...rows[0]!.plots, ...step.set.plots };
              await db.query('UPDATE villages SET plots = $2, levels = $3 WHERE id = $1', [rows[0]!.id, JSON.stringify(plots), JSON.stringify(levelsOf(plots))]);
            }
            for (const tech of step.set.known ?? []) {
              await db.query(
                `INSERT INTO research (world_id, account_id, tech, status, village_id, started_at, completes_at, cost, paid)
                 SELECT $1, owner_account_id, $2, 'done', id, $3, $3, NULL, NULL FROM villages WHERE id = (SELECT min(id) FROM villages WHERE world_id = $1)`,
                [world.id, tech, now],
              );
            }
            if (step.set.researchPoints !== undefined) {
              await db.query('UPDATE world_members SET research_points = $2, research_settled_at = $3 WHERE world_id = $1', [world.id, step.set.researchPoints, now]);
            }
            if (step.set.amounts) {
              await db.query(
                'UPDATE villages SET amounts = amounts || $2::jsonb WHERE id = (SELECT min(id) FROM villages WHERE world_id = $1)',
                [world.id, JSON.stringify(step.set.amounts)],
              );
            }
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
      // Everything the player was told along the way.
      const inbox = await call('GET', `/v1/worlds/${world.id}/notifications`, token);
      recorded.push({ method: 'GET', path: '/v1/worlds/-1/notifications', status: inbox.status, response: toLocalIds(inbox.body, maps) });
      const fixture = { start, steps: recorded };
      if (process.env.UPDATE_FIXTURES) writeFileSync(path, JSON.stringify(fixture, null, 1) + '\n');
      expect(fixture).toEqual(JSON.parse(readFileSync(path, 'utf8')));
    }, timeoutMs);
  });
}
