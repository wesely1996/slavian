import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import WebSocket from 'ws';
import { buildApp } from '../src/api/app.js';
import { LiveHub } from '../src/api/live.js';
import { loadGameData } from '../src/data/index.js';
import type { Db } from '../src/db/pool.js';
import { handlers } from '../src/scheduler/handlers.js';
import { tick } from '../src/scheduler/worker.js';
import { total } from '../src/sim/battle.js';
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
    live = new LiveHub(db, scheduler.data, clock);
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

  it('trains units once a barracks stands and moves them home when done', async () => {
    const mila = await guest('Mila');
    const created = await call('POST', '/v1/worlds', mila.token, { name: 'Solo', maxPlayers: 1, speed: 10 });
    const started = await call('POST', `/v1/worlds/${created.body.id}/start`, mila.token);
    const villageId: number = started.body.villages[0].id;
    expect(started.body.villages[0].garrison).toEqual({});

    const noBarracks = await call('POST', `/v1/villages/${villageId}/train`, mila.token, { unit: 'spearman', count: 2 });
    expect(noBarracks.status).toBe(400);
    expect(noBarracks.body.message).toMatch(/Barracks level 1/);

    const built = await call('POST', `/v1/villages/${villageId}/build`, mila.token, { building: 'barracks' });
    now = new Date(built.body.village.queue[0].completesAt);
    await tick(db, now, scheduler);

    const trained = await call('POST', `/v1/villages/${villageId}/train`, mila.token, { unit: 'spearman', count: 3 });
    expect(trained.status).toBe(200);
    const batch = trained.body.village.training[0];
    expect(batch).toMatchObject({ unit: 'spearman', count: 3, perUnitMs: 6000 });
    expect(trained.body.village.resources.ratesPerHour.grain).toBeCloseTo(
      started.body.villages[0].resources.ratesPerHour.grain - 3 * 10,
    );
    expect((await call('POST', `/v1/villages/${villageId}/train`, mila.token, { unit: 'horseman', count: 1 })).body.message).toMatch(
      /Barracks level 2/,
    );
    expect((await call('POST', `/v1/villages/${villageId}/train`, mila.token, { unit: 'spearman', count: 0 })).status).toBe(400);

    now = new Date(batch.completesAt);
    await tick(db, now, scheduler);
    const world = await call('GET', `/v1/worlds/${created.body.id}`, mila.token);
    expect(world.body.villages[0].garrison).toEqual({ spearman: 3 });
    expect(world.body.villages[0].training).toEqual([]);
  });

  it('announces waves when a world starts and runs them through the scheduler', async () => {
    const ratimir = await guest('Ratimir');
    const created = await call('POST', '/v1/worlds', ratimir.token, { name: 'Waves', maxPlayers: 1, speed: 10 });
    const worldId: number = created.body.id;
    const started = await call('POST', `/v1/worlds/${worldId}/start`, ratimir.token);
    const village = started.body.villages[0];

    const announced = started.body.waves;
    expect(announced.map((w: { index: number }) => w.index)).toEqual([0, 1]);
    expect(announced[0]).toMatchObject({ front: 'north', status: 'scheduled', path: null, targetVillageId: null });
    expect(['Low', 'Moderate', 'High', 'Severe']).toContain(announced[0].threat);
    // Composition stays secret.
    expect(JSON.stringify(started.body)).not.toMatch(/composition|grey_wolf|leshy/);
    // Grace period: one week of game time, at 10x speed.
    expect(new Date(announced[0].spawnAt).getTime() - new Date(started.body.startedAt).getTime()).toBe((168 * 3_600_000) / 10);

    const getWaves = async () => (await call('GET', `/v1/worlds/${worldId}`, ratimir.token)).body.waves;

    now = new Date(announced[0].spawnAt);
    await tick(db, now, scheduler);
    let waves = await getWaves();
    expect(waves.map((w: { index: number }) => w.index)).toEqual([0, 1, 2]);
    const marching = waves[0];
    expect(marching.status).toBe('marching');
    expect(marching.targetVillageId).toBe(village.id);
    expect(marching.path.at(-1).slice(0, 2)).toEqual([village.q, village.r]);
    expect(new Date(marching.arrivesAt).getTime()).toBe(now.getTime() + marching.path.at(-1)[2]);

    // Arriving opens a battle against the (empty) garrison.
    now = new Date(marching.arrivesAt);
    await tick(db, now, scheduler);
    let world = (await call('GET', `/v1/worlds/${worldId}`, ratimir.token)).body;
    expect(world.waves[0]).toMatchObject({ index: 0, status: 'battling' });
    const battle = world.battles[0];
    expect(battle).toMatchObject({ waveId: marching.id, villageId: village.id, status: 'ongoing', round: 0, defenderInitial: {} });
    expect(battle.attackerStance).toBeTruthy();

    // No defenders: the first round ends in a raid.
    now = new Date(now.getTime() + (15 * 60_000) / 10);
    await tick(db, now, scheduler);
    world = (await call('GET', `/v1/worlds/${worldId}`, ratimir.token)).body;
    const raided = world.battles[0];
    expect(raided).toMatchObject({ status: 'raided', round: 1 });
    // The whole horde survived, so it carried off 30% of what was stored.
    const left = world.villages[0].resources;
    expect(left.settledAt).toBe(now.toISOString());
    for (const kind of ['wood', 'stone', 'grain', 'iron']) {
      const stored = left.amounts[kind] + raided.loot[kind];
      expect(raided.loot[kind]).toBe(Math.floor(stored * 0.3));
    }
    expect(world.waves.map((w: { index: number }) => w.index)).toEqual([1, 2]);
  });

  it('sends scouts at a wave and shares their report', async () => {
    const zora = await guest('Zora');
    const created = await call('POST', '/v1/worlds', zora.token, { name: 'Scouts', maxPlayers: 1, speed: 10 });
    const worldId: number = created.body.id;
    const started = await call('POST', `/v1/worlds/${worldId}/start`, zora.token);
    const villageId: number = started.body.villages[0].id;
    const waveId: number = started.body.waves[0].id;

    expect((await call('POST', `/v1/villages/${villageId}/scout`, zora.token, { waveId, count: 1 })).body.message).toMatch(/Only 0 scout/);

    const lodge = await call('POST', `/v1/villages/${villageId}/build`, zora.token, { building: 'scout_lodge' });
    now = new Date(lodge.body.village.queue[0].completesAt);
    await tick(db, now, scheduler);
    const trained = await call('POST', `/v1/villages/${villageId}/train`, zora.token, { unit: 'scout', count: 6 });
    now = new Date(trained.body.village.training[0].completesAt);
    await tick(db, now, scheduler);

    expect((await call('POST', `/v1/villages/${villageId}/scout`, zora.token, { waveId, count: 0 })).status).toBe(400);
    expect((await call('POST', `/v1/villages/${villageId}/scout`, zora.token, { waveId: 999999, count: 1 })).status).toBe(404);

    const sent = await call('POST', `/v1/villages/${villageId}/scout`, zora.token, { waveId, count: 6 });
    expect(sent.status).toBe(200);
    expect(sent.body.village.garrison.scout).toBe(0);
    expect(sent.body.village.away.scout).toBe(6);
    const mission = sent.body.mission;
    expect(mission).toMatchObject({ waveId, sent: 6, status: 'outbound', report: null });

    now = new Date(mission.arrivesAt);
    await tick(db, now, scheduler);
    let world = (await call('GET', `/v1/worlds/${worldId}`, zora.token)).body;
    const reported = world.scouting.find((m: { id: number }) => m.id === mission.id);
    expect(reported.status).toBe('returning');
    const report = reported.report;
    expect(report.sent).toBe(6);
    expect(report.survivors).toBeLessThanOrEqual(6);
    if (report.survivors >= 6) expect(report.tier).toBe('exact');
    if (report.survivors > 0) expect(report.size.min).toBeLessThanOrEqual(report.size.max);
    // Dead scouts are gone from the village.
    expect(world.villages[0].away.scout).toBe(report.survivors);
    // The wave itself still doesn't leak its composition.
    expect(JSON.stringify(world.waves)).not.toMatch(/composition|grey_wolf/);

    now = new Date(mission.returnsAt);
    await tick(db, now, scheduler);
    world = (await call('GET', `/v1/worlds/${worldId}`, zora.token)).body;
    expect(world.scouting.find((m: { id: number }) => m.id === mission.id).status).toBe('done');
    expect(world.villages[0].garrison.scout).toBe(report.survivors);
    expect(world.villages[0].away.scout).toBe(0);
  });

  it('a garrison fights off a wave, round by round, with its stance', async () => {
    const dobran = await guest('Dobran');
    const created = await call('POST', '/v1/worlds', dobran.token, { name: 'Battle', maxPlayers: 1, speed: 10 });
    const worldId: number = created.body.id;
    const started = await call('POST', `/v1/worlds/${worldId}/start`, dobran.token);
    const villageId: number = started.body.villages[0].id;
    const wave = started.body.waves[0];
    expect(started.body.villages[0].stance).toBe('balanced');

    expect((await call('POST', `/v1/villages/${villageId}/stance`, dobran.token, { stance: 'reckless' })).status).toBe(400);
    const stance = await call('POST', `/v1/villages/${villageId}/stance`, dobran.token, { stance: 'hold_the_line' });
    expect(stance.body.village.stance).toBe('hold_the_line');

    // Fill the stores so we can afford a proper garrison.
    await db.query(`UPDATE villages SET amounts = '{"wood": 9000, "stone": 9000, "grain": 9000, "iron": 9000}' WHERE id = $1`, [villageId]);
    const barracks = await call('POST', `/v1/villages/${villageId}/build`, dobran.token, { building: 'barracks' });
    now = new Date(barracks.body.village.queue[0].completesAt);
    await tick(db, now, scheduler);
    await call('POST', `/v1/villages/${villageId}/train`, dobran.token, { unit: 'spearman', count: 20 });

    now = new Date(wave.spawnAt);
    await tick(db, now, scheduler);
    const marching = (await call('GET', `/v1/worlds/${worldId}`, dobran.token)).body.waves[0];
    now = new Date(marching.arrivesAt);
    await tick(db, now, scheduler);

    let world = (await call('GET', `/v1/worlds/${worldId}`, dobran.token)).body;
    let battle = world.battles[0];
    expect(battle.defenderInitial).toEqual({ spearman: 20 });
    expect(battle.attackerNow).toEqual(battle.attackerInitial);

    const roundMs = (15 * 60_000) / 10;
    for (let round = 1; round <= 12 && battle.status === 'ongoing'; round++) {
      now = new Date(now.getTime() + roundMs);
      await tick(db, now, scheduler);
      world = (await call('GET', `/v1/worlds/${worldId}`, dobran.token)).body;
      battle = world.battles[0];
      expect(battle.round).toBe(round);
    }
    expect(battle.status).toBe('defended');
    expect(battle.loot).toBeNull();
    const last = battle.rounds.at(-1);
    expect(last.defenderLeft).toBe(world.villages[0].garrison.spearman ?? 0);
    expect(total(battle.attackerNow)).toBe(last.attackerLeft);
    // The beaten wave leaves the board; the next ones remain.
    expect(world.waves.map((w: { index: number }) => w.index)).toEqual([1, 2]);
    // Fallen spearmen stop eating.
    const fallen = 20 - (world.villages[0].garrison.spearman ?? 0);
    expect(world.villages[0].resources.ratesPerHour.grain).toBeCloseTo(started.body.villages[0].resources.ratesPerHour.grain - (20 - fallen) * 10);
  });

  it('builds on plots: fields, free slots and the Elder\'s Hall', async () => {
    const lada = await guest('Lada');
    const created = await call('POST', '/v1/worlds', lada.token, { name: 'Plots', maxPlayers: 1, speed: 10 });
    const started = await call('POST', `/v1/worlds/${created.body.id}/start`, lada.token);
    const village = started.body.villages[0];
    expect(village.plots.c0).toEqual({ building: 'elder_hall', level: 1 });
    expect(village.plots.f0.level).toBe(0);
    const build = (body: object) => call('POST', `/v1/villages/${village.id}/build`, lada.token, body);

    expect((await build({})).status).toBe(400);
    expect((await build({ plot: 'zz' })).status).toBe(400);
    expect((await build({ plot: 'c9', building: 'barracks' })).body.message).toMatch(/locked/);
    const field = await build({ plot: 'f4' });
    expect(field.status).toBe(200);
    expect(field.body.village.queue[0]).toMatchObject({ plot: 'f4', building: 'quarry', targetLevel: 1 });
    const slot = await build({ plot: 'c3', building: 'barracks' });
    expect(slot.body.village.queue[1]).toMatchObject({ plot: 'c3', building: 'barracks', targetLevel: 1 });

    now = new Date(slot.body.village.queue[1].completesAt);
    await tick(db, now, scheduler);
    const world = await call('GET', `/v1/worlds/${created.body.id}`, lada.token);
    expect(world.body.villages[0].plots.f4).toEqual({ building: 'quarry', level: 1 });
    expect(world.body.villages[0].plots.c3).toEqual({ building: 'barracks', level: 1 });
  });

  it('claims outposts, which hordes burn as they pass and sieges cut off', async () => {
    const zora = await guest('Zora');
    const created = await call('POST', '/v1/worlds', zora.token, { name: 'Outposts', maxPlayers: 1, speed: 10 });
    const worldId: number = created.body.id;
    const started = await call('POST', `/v1/worlds/${worldId}/start`, zora.token);
    const village = started.body.villages[0];
    const home = hex(village.q, village.r);
    const yields = scheduler.data.buildings.buildings.outpost!.yields!;
    const sites = (started.body.map.hexes as [number, number, string][]).filter(
      ([q, r, terrain]) => hexDistance(hex(q, r), home) === 1 && terrain in yields,
    );
    expect(sites.length).toBeGreaterThanOrEqual(2);
    const [[q1, r1, t1], [q2, r2]] = sites as [[number, number, string], [number, number, string]];
    const claim = (q: number, r: number) => call('POST', `/v1/villages/${village.id}/outposts`, zora.token, { q, r });
    await db.query(`UPDATE villages SET amounts = '{"wood": 9000, "stone": 9000, "grain": 9000, "iron": 9000}' WHERE id = $1`, [village.id]);

    expect((await claim(village.q, village.r)).body.message).toMatch(/within 2 hexes/);
    expect((await claim(village.q + 5, village.r)).body.message).toMatch(/within 2 hexes|not on the map/);
    // A bigger Elder's Hall allows a second outpost.
    const hall = await call('POST', `/v1/villages/${village.id}/build`, zora.token, { plot: 'c0' });
    now = new Date(hall.body.village.queue[0].completesAt);
    await tick(db, now, scheduler);

    const first = await claim(q1, r1);
    expect(first.status).toBe(200);
    expect(first.body.village.plots[`o${q1},${r1}`]).toEqual({ building: 'outpost', level: 0, terrain: t1 });
    expect((await claim(q1, r1)).body.message).toMatch(/already taken/);
    now = new Date(first.body.village.queue[0].completesAt);
    await tick(db, now, scheduler);
    let world = (await call('GET', `/v1/worlds/${worldId}`, zora.token)).body;
    expect(world.villages[0].plots[`o${q1},${r1}`].level).toBe(1);
    expect(world.villages[0].levels.outpost).toBeUndefined();

    // The first horde sets out; a second outpost goes up while it marches.
    now = new Date(world.waves[0].spawnAt);
    await tick(db, now, scheduler);
    const second = await claim(q2, r2);
    now = new Date(second.body.village.queue[0].completesAt);
    await tick(db, now, scheduler);
    world = (await call('GET', `/v1/worlds/${worldId}`, zora.token)).body;
    const rates = world.villages[0].resources.ratesPerHour;
    expect(world.villages[0].plots[`o${q2},${r2}`].level).toBe(1);

    // It burns both as it reaches the village, then lays siege.
    now = new Date(world.waves[0].arrivesAt);
    await tick(db, now, scheduler);
    world = (await call('GET', `/v1/worlds/${worldId}`, zora.token)).body;
    expect(world.villages[0].plots[`o${q1},${r1}`].level).toBe(0);
    expect(world.villages[0].plots[`o${q2},${r2}`].level).toBe(0);
    expect(world.raids.map((r: { q: number; r: number }) => `${r.q},${r.r}`).sort()).toEqual([`${q1},${r1}`, `${q2},${r2}`].sort());
    expect(world.raids[0]).toMatchObject({ villageId: village.id, waveId: world.waves[0].id, levelAfter: 0 });
    expect(world.villages[0].besieged).toBe(true);
    expect(world.villages[0].resources.ratesPerHour.grain).toBeLessThanOrEqual(rates.grain);

    while (world.battles[0]?.status === 'ongoing') {
      now = new Date(now.getTime() + (15 * 60_000) / 10);
      await tick(db, now, scheduler);
      world = (await call('GET', `/v1/worlds/${worldId}`, zora.token)).body;
    }
    expect(world.villages[0].besieged).toBe(false);

    // Ruins can be abandoned.
    const abandoned = await call('POST', `/v1/villages/${village.id}/outposts/abandon`, zora.token, { q: q1, r: r1 });
    expect(abandoned.body.village.plots[`o${q1},${r1}`]).toBeUndefined();
  });

  it('sends caravans to an ally and to the vault, fetches from it and enlarges it', async () => {
    const vid = await guest('Vid');
    const ola = await guest('Ola');
    const created = await call('POST', '/v1/worlds', vid.token, { name: 'Caravans', maxPlayers: 2, speed: 10 });
    const worldId: number = created.body.id;
    await call('POST', '/v1/worlds/join', ola.token, { inviteCode: created.body.inviteCode });
    const started = await call('POST', `/v1/worlds/${worldId}/start`, vid.token);
    expect(started.body.vault).toMatchObject({ level: 1, amounts: { wood: 0, stone: 0, grain: 0, iron: 0 }, capacity: 3000 });
    const mine = started.body.villages.find((v: { ownerAccountId: number }) => v.ownerAccountId === vid.accountId);
    const theirs = started.body.villages.find((v: { ownerAccountId: number }) => v.ownerAccountId === ola.accountId);
    const send = (body: object) => call('POST', `/v1/villages/${mine.id}/caravans`, vid.token, body);
    const load = (wood = 0, stone = 0, grain = 0, iron = 0) => ({ wood, stone, grain, iron });
    const world = async () => (await call('GET', `/v1/worlds/${worldId}`, vid.token)).body;

    expect((await send({ destinationVillageId: theirs.id, load: load(100) })).body.message).toMatch(/Caravan Yard first/);
    const yard = await call('POST', `/v1/villages/${mine.id}/build`, vid.token, { building: 'caravan_yard' });
    now = new Date(yard.body.village.queue[0].completesAt);
    await tick(db, now, scheduler);
    await db.query(`UPDATE villages SET amounts = '{"wood": 2000, "stone": 2000, "grain": 2000, "iron": 2000}', capacity = '{"wood": 5000, "stone": 5000, "grain": 5000, "iron": 5000}' WHERE id = $1`, [mine.id]);

    expect((await send({ destinationVillageId: theirs.id, load: load(400, 200) })).body.message).toMatch(/takes 2 caravans; 1 at home/);
    expect((await send({ destinationVillageId: mine.id, load: load(100) })).body.message).toMatch(/another village/);
    expect((await send({ destinationVillageId: theirs.id, load: load() })).body.message).toMatch(/Nothing to carry/);
    expect((await send({ load: load(-1) })).status).toBe(400);

    // 400 wood and 100 iron to Ola: she has room for 500 more of each.
    const trip = await send({ destinationVillageId: theirs.id, load: load(400, 0, 0, 100) });
    expect(trip.status).toBe(200);
    expect(trip.body.caravan).toMatchObject({ kind: 'deliver', caravans: 1, status: 'outbound', destinationVillageId: theirs.id });
    expect(trip.body.village.resources.amounts.wood).toBeLessThanOrEqual(1600 + 1);
    expect((await send({ load: load(10) })).body.message).toMatch(/0 at home/);
    now = new Date(trip.body.caravan.arrivesAt);
    await tick(db, now, scheduler);
    let w = await world();
    const ola1 = w.villages.find((v: { id: number }) => v.id === theirs.id);
    expect(ola1.resources.amounts.wood).toBeGreaterThanOrEqual(900);
    expect(w.caravans[0]).toMatchObject({ status: 'returning', carriedBack: load() });
    now = new Date(trip.body.caravan.returnsAt);
    await tick(db, now, scheduler);
    expect((await world()).caravans[0].status).toBe('done');

    // To the vault, and back out again.
    const deposit = await send({ load: load(500) });
    expect(deposit.body.caravan.destinationVillageId).toBeNull();
    now = new Date(deposit.body.caravan.returnsAt);
    await tick(db, now, scheduler);
    expect((await world()).vault.amounts.wood).toBe(500);
    const fetch = await call('POST', `/v1/villages/${mine.id}/caravans/fetch`, vid.token, { load: load(300, 100) });
    expect(fetch.body.caravan).toMatchObject({ kind: 'fetch', cargo: load(300, 100) });
    const woodBefore = fetch.body.village.resources.amounts.wood;
    now = new Date(fetch.body.caravan.arrivesAt);
    await tick(db, now, scheduler);
    w = await world();
    expect(w.vault.amounts).toEqual(load(200));
    expect(w.caravans[0].carriedBack).toEqual(load(300));
    now = new Date(fetch.body.caravan.returnsAt);
    await tick(db, now, scheduler);
    const home = (await world()).villages.find((v: { id: number }) => v.id === mine.id);
    expect(home.resources.amounts.wood).toBeGreaterThanOrEqual(woodBefore + 300);

    // Enlarging the vault is paid from the vault.
    expect((await call('POST', `/v1/worlds/${worldId}/vault/upgrade`, ola.token)).body.message).toMatch(/needs more wood, stone, grain, iron/);
    await db.query(`UPDATE vaults SET amounts = '{"wood": 3000, "stone": 3000, "grain": 3000, "iron": 3000}' WHERE world_id = $1`, [worldId]);
    const upgrade = await call('POST', `/v1/worlds/${worldId}/vault/upgrade`, ola.token);
    expect(upgrade.body.vault).toMatchObject({ level: 1, upgradingTo: 2, amounts: load(2200, 2000, 2600, 2600) });
    expect((await call('POST', `/v1/worlds/${worldId}/vault/upgrade`, ola.token)).body.message).toMatch(/already being enlarged/);
    now = new Date(upgrade.body.vault.upgradeCompletesAt);
    await tick(db, now, scheduler);
    expect((await world()).vault).toMatchObject({ level: 2, upgradingTo: null, capacity: 4500 });
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
