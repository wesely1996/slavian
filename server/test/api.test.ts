import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import WebSocket from 'ws';
import { buildApp } from '../src/api/app.js';
import { LiveHub } from '../src/api/live.js';
import { loadGameData } from '../src/data/index.js';
import type { Db } from '../src/db/pool.js';
import { handlers } from '../src/scheduler/handlers.js';
import { tick } from '../src/scheduler/worker.js';
import { hex, hexDistance } from '../src/sim/hex.js';
import { createTestDb, TEST_DATABASE_URL } from './db.js';

const scheduler = { data: loadGameData(), handlers };

describe.skipIf(!TEST_DATABASE_URL)('api (postgres)', () => {
  let db: Db;
  let cleanup: () => Promise<void>;
  let app: FastifyInstance;
  let live: LiveHub;
  let baseUrl: string;
  let now = new Date('2026-05-01T10:00:00Z');
  const clock = () => now;

  beforeAll(async () => {
    ({ db, cleanup } = await createTestDb());
    live = new LiveHub(db, clock);
    await live.start();
    app = await buildApp({ db, scheduler, clock, live });
    await app.listen({ port: 0, host: '127.0.0.1' });
    const address = app.server.address();
    baseUrl = `127.0.0.1:${typeof address === 'object' && address ? address.port : 0}`;
  });
  afterAll(async () => {
    await app?.close();
    await live?.stop();
    await cleanup?.();
  });

  async function call(method: string, url: string, token?: string, body?: unknown) {
    const response = await app.inject({
      method: method as 'GET',
      url,
      headers: token ? { authorization: `Bearer ${token}` } : {},
      ...(body === undefined ? {} : { payload: body as object }),
    });
    return { status: response.statusCode, body: response.json() };
  }

  async function guest(displayName: string): Promise<{ token: string; accountId: number }> {
    const { status, body } = await call('POST', '/v1/auth/guest', undefined, { displayName });
    expect(status).toBe(200);
    return { token: body.token, accountId: body.account.id };
  }

  it('rejects requests without a valid token', async () => {
    expect((await call('GET', '/v1/me')).status).toBe(401);
    expect((await call('GET', '/v1/me', 'nope')).status).toBe(401);
  });

  it('serves game data publicly', async () => {
    const { status, body } = await call('GET', '/v1/data');
    expect(status).toBe(200);
    expect(body.buildings.buildings.woodcutter.name).toBe('Woodcutter');
    expect(body.terrain.terrain.plains.settleable).toBe(true);
  });

  it('runs the lobby -> start -> build flow for two players', async () => {
    const vesna = await guest('Vesna');
    const bogdan = await guest('Bogdan');
    const stranger = await guest('Stranger');

    const created = await call('POST', '/v1/worlds', vesna.token, { name: 'Pilot', maxPlayers: 2, speed: 10 });
    expect(created.status).toBe(200);
    expect(created.body.status).toBe('lobby');
    expect(created.body.inviteCode).toMatch(/^[A-Z2-9]{6}$/);
    const worldId: number = created.body.id;

    // Only members can see the world; codes are case-insensitive.
    expect((await call('GET', `/v1/worlds/${worldId}`, bogdan.token)).status).toBe(404);
    const joined = await call('POST', '/v1/worlds/join', bogdan.token, {
      inviteCode: created.body.inviteCode.toLowerCase(),
    });
    expect(joined.status).toBe(200);
    expect(joined.body.members.map((m: { displayName: string }) => m.displayName)).toEqual(['Vesna', 'Bogdan']);
    expect((await call('POST', '/v1/worlds/join', stranger.token, { inviteCode: created.body.inviteCode })).body.error).toBe('rule');

    // Only the host starts it.
    expect((await call('POST', `/v1/worlds/${worldId}/start`, bogdan.token)).status).toBe(403);
    const started = await call('POST', `/v1/worlds/${worldId}/start`, vesna.token);
    expect(started.status).toBe(200);
    expect(started.body.status).toBe('running');
    expect(started.body.map.activeFronts).toEqual(['north', 'south', 'east']);
    expect(started.body.map.hexes.length).toBeGreaterThan(300);
    expect(started.body.villages).toHaveLength(2);
    for (const v of started.body.villages) expect(hexDistance(hex(v.q, v.r), hex(0, 0))).toBe(2);
    expect((await call('POST', `/v1/worlds/${worldId}/start`, vesna.token)).body.error).toBe('rule');

    const me = await call('GET', '/v1/me', bogdan.token);
    expect(me.body.worlds.map((w: { id: number }) => w.id)).toContain(worldId);

    const vesnaVillage = started.body.villages.find((v: { ownerAccountId: number }) => v.ownerAccountId === vesna.accountId);
    // Teammates can see but not command each other's villages.
    expect((await call('POST', `/v1/villages/${vesnaVillage.id}/build`, bogdan.token, { building: 'farm' })).status).toBe(403);
    expect((await call('POST', `/v1/villages/${vesnaVillage.id}/build`, vesna.token, { building: 'castle' })).body.error).toBe('rule');

    // Live updates: subscribe, queue a build, then let the scheduler finish it.
    const socket = new WebSocket(`ws://${baseUrl}/v1/live`, { headers: { authorization: `Bearer ${bogdan.token}` } });
    const messages: { type: string; [key: string]: unknown }[] = [];
    const waitFor = (predicate: (m: (typeof messages)[number]) => boolean) =>
      new Promise<(typeof messages)[number]>((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error(`Timed out; got ${JSON.stringify(messages)}`)), 5000);
        const check = () => {
          const found = messages.find(predicate);
          if (found) {
            clearTimeout(timer);
            resolve(found);
          } else setTimeout(check, 20);
        };
        check();
      });
    socket.on('message', (raw) => messages.push(JSON.parse(raw.toString())));
    await new Promise((resolve) => socket.once('open', resolve));
    socket.send(JSON.stringify({ type: 'subscribe', worldId }));
    await waitFor((m) => m.type === 'subscribed');

    const built = await call('POST', `/v1/villages/${vesnaVillage.id}/build`, vesna.token, { building: 'farm' });
    expect(built.status).toBe(200);
    expect(built.body.village.queue).toHaveLength(1);
    const queuedPush = await waitFor((m) => m.type === 'village');
    expect((queuedPush.village as { queue: unknown[] }).queue).toHaveLength(1);

    now = new Date(built.body.village.queue[0].completesAt);
    await tick(db, now, scheduler);
    const donePush = await waitFor(
      (m) => m.type === 'village' && (m.village as { levels: Record<string, number> }).levels.farm === 1,
    );
    expect((donePush.village as { queue: unknown[] }).queue).toHaveLength(0);
    socket.close();
  });

  it('refuses live subscriptions to worlds you are not in', async () => {
    const outsider = await guest('Outsider');
    const host = await guest('Host');
    const world = await call('POST', '/v1/worlds', host.token, { name: 'Private' });
    const socket = new WebSocket(`ws://${baseUrl}/v1/live`, { headers: { authorization: `Bearer ${outsider.token}` } });
    await new Promise((resolve) => socket.once('open', resolve));
    const reply = new Promise<{ type: string }>((resolve) => socket.once('message', (raw) => resolve(JSON.parse(raw.toString()))));
    socket.send(JSON.stringify({ type: 'subscribe', worldId: world.body.id }));
    expect((await reply).type).toBe('error');
    socket.close();
  });

  it('rejects live connections without a token', async () => {
    const socket = new WebSocket(`ws://${baseUrl}/v1/live`);
    const status = await new Promise<number>((resolve) => socket.once('unexpected-response', (_, res) => resolve(res.statusCode ?? 0)));
    expect(status).toBe(401);
  });
});
