import type { FastifyInstance } from 'fastify';
import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';
import WebSocket from 'ws';
import { buildApp } from '../src/api/app.js';
import { LiveHub } from '../src/api/live.js';
import { loadGameData, type TerrainId } from '../src/data/index.js';
import type { Db } from '../src/db/pool.js';
import { handlers } from '../src/scheduler/handlers.js';
import { tick } from '../src/scheduler/worker.js';
import { pushPending } from '../src/push/worker.js';
import { total } from '../src/sim/battle.js';
import { hex, hexDistance } from '../src/sim/hex.js';
import { rosterBonuses } from '../src/sim/heroes.js';
import { roadRoute } from '../src/sim/logistics.js';
import { createTestDb, TEST_DATABASE_URL } from './db.js';

const scheduler = { data: loadGameData(), handlers };

// A spearman's grain an hour under Dobrynya, the hero of anyone who doesn't pick.
const DOBRYNYA_UPKEEP = 10 * (1 + rosterBonuses(loadGameData(), 'dobrynya').upkeep!);

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
  // Each test plays its own world; once it is done, end it so later ticks
  // don't keep playing it out.
  afterEach(async () => {
    await db.query("UPDATE worlds SET status = 'won' WHERE status = 'running'");
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
    expect((await call('GET', '/health')).body).toEqual({ ok: true });
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

    // Each picks a hero from the roster; no two the same.
    expect((await call('PUT', `/v1/worlds/${worldId}/hero`, bogdan.token, { kind: 'vasilisa' })).status).toBe(200);
    expect((await call('PUT', `/v1/worlds/${worldId}/hero`, vesna.token, { kind: 'vasilisa' })).body.message).toMatch(/someone else/);
    expect((await call('PUT', `/v1/worlds/${worldId}/hero`, vesna.token, { kind: 'nobody' })).body.error).toBe('rule');

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

    // Bogdan rides with Vasilisa; Vesna, who didn't pick, got another hero.
    const kinds = new Map(started.body.members.map((m: { accountId: number; heroKind: string }) => [m.accountId, m.heroKind]));
    expect(kinds.get(bogdan.accountId)).toBe('vasilisa');
    expect(kinds.get(vesna.accountId)).toMatch(/^(?!vasilisa$)\w+$/);
    expect((await call('PUT', `/v1/worlds/${worldId}/hero`, bogdan.token, { kind: 'volkh' })).body.message).toMatch(/chosen for this run/);

    const me = await call('GET', '/v1/me', bogdan.token);
    expect(me.body.worlds.map((w: { id: number }) => w.id)).toContain(worldId);

    const vesnaVillage = started.body.villages.find((v: { ownerAccountId: number }) => v.ownerAccountId === vesna.accountId);
    // Every town has a name of its own, which its owner can change.
    const names = started.body.villages.map((v: { name: string }) => v.name);
    expect(new Set(names).size).toBe(2);
    for (const name of names) expect(name).not.toMatch(/'s village/);
    expect((await call('POST', `/v1/villages/${vesnaVillage.id}/rename`, bogdan.token, { name: 'Mine' })).status).toBe(403);
    expect((await call('POST', `/v1/villages/${vesnaVillage.id}/rename`, vesna.token, { name: '  ' })).status).toBe(400);
    const renamed = await call('POST', `/v1/villages/${vesnaVillage.id}/rename`, vesna.token, { name: ' Kitezh ' });
    expect(renamed.status).toBe(200);
    expect(renamed.body.village.name).toBe('Kitezh');
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
    // Mila didn't pick, so she rides with the first hero, Dobrynya, whose retinue eats more.
    expect(trained.body.village.resources.ratesPerHour.grain).toBeCloseTo(
      started.body.villages[0].resources.ratesPerHour.grain - 3 * DOBRYNYA_UPKEEP,
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
    expect(battle).toMatchObject({ waveId: marching.id, front: marching.front, villageId: village.id, status: 'ongoing', round: 0, defenderInitial: {} });
    expect(battle.attackerStance).toBeTruthy();

    // Work started just before the round; the raid will burn it.
    const roundAt = now.getTime() + (15 * 60_000) / 10;
    now = new Date(roundAt - 10_000);
    const building = (await call('POST', `/v1/villages/${village.id}/build`, ratimir.token, { plot: 'c0' })).body.village.queue[0];
    expect(new Date(building.completesAt).getTime()).toBeGreaterThan(roundAt);

    // No defenders: the first round ends in a raid.
    now = new Date(roundAt);
    await tick(db, now, scheduler);
    world = (await call('GET', `/v1/worlds/${worldId}`, ratimir.token)).body;
    const raided = world.battles[0];
    expect(raided).toMatchObject({ status: 'raided', round: 1 });
    expect(world.villages[0].queue).toEqual([]);
    // The whole horde survived, so it carried off 30% of what was stored,
    // scaled by its faction's greed (monsters care little for loot).
    const left = world.villages[0].resources;
    expect(left.settledAt).toBe(now.toISOString());
    const share = 0.3 * scheduler.data.enemies.fronts.north!.personality.lootFactor;
    for (const kind of ['wood', 'stone', 'grain', 'iron']) {
      const stored = left.amounts[kind] + raided.loot[kind];
      expect(Math.abs(raided.loot[kind] - Math.floor(stored * share))).toBeLessThanOrEqual(1);
    }
    // Its first raid done, the horde moves on (or makes camp) and remembers
    // where it struck; early hordes only raid.
    const after = world.waves.find((w: { index: number }) => w.index === 0);
    expect(raided.decision).toEqual({ choice: 'raid', reasons: ['an early raiding party'] });
    if (after) {
      expect(after.struck).toEqual([village.id]);
      expect(after.status).toBe('marching');
    }
    // The burned build's completion passes quietly.
    now = new Date(new Date(building.completesAt).getTime() + 1000);
    await tick(db, now, scheduler);
    const failed = await db.query("SELECT 1 FROM scheduled_events WHERE world_id = $1 AND status = 'failed'", [worldId]);
    expect(failed.rowCount).toBe(0);
    expect((await call('GET', `/v1/worlds/${worldId}`, ratimir.token)).body.villages[0].levels.elder_hall).toBe(1);
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
    // Hordes remember where they were beaten.
    expect(world.fear).toEqual([[world.villages[0].q, world.villages[0].r, expect.any(Number)]]);
    const last = battle.rounds.at(-1);
    expect(last.defenderLeft).toBe(world.villages[0].garrison.spearman ?? 0);
    expect(total(battle.attackerNow)).toBe(last.attackerLeft);
    // The beaten wave leaves the board; the next ones remain.
    expect(world.waves.map((w: { index: number }) => w.index)).toEqual([1, 2]);
    // Fallen spearmen stop eating.
    const fallen = 20 - (world.villages[0].garrison.spearman ?? 0);
    expect(world.villages[0].resources.ratesPerHour.grain).toBeCloseTo(started.body.villages[0].resources.ratesPerHour.grain - (20 - fallen) * DOBRYNYA_UPKEEP);
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
    // Less the load, plus the first-gift reward (data/onboarding.json).
    const gift = scheduler.data.onboarding.steps.find((s) => s.id === 'gift')!.reward;
    expect(trip.body.village.resources.amounts.wood).toBeLessThanOrEqual(1600 + gift.wood + 1);
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

  it('sends settlers to found a second village, which pays upkeep and makes settlers dearer', async () => {
    const mila = await guest('Mila');
    const created = await call('POST', '/v1/worlds', mila.token, { name: 'Expansion', maxPlayers: 1, speed: 10 });
    const worldId: number = created.body.id;
    const started = await call('POST', `/v1/worlds/${worldId}/start`, mila.token);
    const home = started.body.villages[0];
    const homeCell = hex(home.q, home.r);
    const rich = () =>
      db.query(
        `UPDATE villages SET amounts = '{"wood": 5000, "stone": 5000, "grain": 5000, "iron": 5000}', capacity = '{"wood": 9000, "stone": 9000, "grain": 9000, "iron": 9000}' WHERE id = $1`,
        [home.id],
      );
    const found = (q: number, r: number, name?: string) =>
      call('POST', `/v1/villages/${home.id}/found`, mila.token, { q, r, ...(name ? { name } : {}) });

    const settleable = new Set(['plains', 'forest', 'hills']);
    const ancient = new Set(started.body.sites.map((s: { q: number; r: number }) => `${s.q},${s.r}`));
    const site = (started.body.map.hexes as [number, number, string][]).find(
      ([q, r, t]) => settleable.has(t) && hexDistance(hex(q, r), homeCell) === 4 && hexDistance(hex(q, r), hex(0, 0)) >= 3 && !ancient.has(`${q},${r}`),
    )!;
    expect(site).toBeDefined();
    expect((await found(site[0], site[1])).body.message).toMatch(/takes 3 settlers/);
    expect((await found(home.q + 1, home.r)).body.message).toMatch(/apart/);

    const lodge = await call('POST', `/v1/villages/${home.id}/build`, mila.token, { building: 'settlers_lodge' });
    now = new Date(lodge.body.village.queue[0].completesAt);
    await tick(db, now, scheduler);
    await rich();
    const trained = await call('POST', `/v1/villages/${home.id}/train`, mila.token, { unit: 'settler', count: 3 });
    expect(trained.status).toBe(200);
    now = new Date(trained.body.village.training[0].completesAt);
    await tick(db, now, scheduler);

    const sent = await found(site[0], site[1], 'Vesna');
    expect(sent.status).toBe(200);
    expect(sent.body.expedition).toMatchObject({ q: site[0], r: site[1], name: 'Vesna', settlers: 3, status: 'outbound' });
    expect(sent.body.village.away.settler).toBe(3);
    expect((await found(site[0], site[1])).body.message).toMatch(/takes 3 settlers|already on their way/);

    now = new Date(sent.body.expedition.arrivesAt);
    await tick(db, now, scheduler);
    let world = (await call('GET', `/v1/worlds/${worldId}`, mila.token)).body;
    expect(world.villages).toHaveLength(2);
    const second = world.villages.find((v: { name: string }) => v.name === 'Vesna');
    expect(second).toMatchObject({ q: site[0], r: site[1], ownerAccountId: mila.accountId, adminUpkeep: scheduler.data.expansion.adminUpkeepPerVillage });
    expect(second.resources.amounts).toEqual(scheduler.data.expansion.startingResources);
    expect(world.villages.find((v: { id: number }) => v.id === home.id).away.settler ?? 0).toBe(0);
    expect(world.expeditions[0]).toMatchObject({ status: 'founded', foundedVillageId: second.id });

    // A second village makes the next settlers dearer.
    await rich();
    const before = (await call('GET', `/v1/worlds/${worldId}`, mila.token)).body.villages.find((v: { id: number }) => v.id === home.id);
    const dearer = await call('POST', `/v1/villages/${home.id}/train`, mila.token, { unit: 'settler', count: 1 });
    const spentWood = before.resources.amounts.wood - dearer.body.village.resources.amounts.wood;
    expect(spentWood).toBeGreaterThan(scheduler.data.units.units.settler!.cost.wood * 1.4);

    // Settlers find their site taken: they come home.
    now = new Date(dearer.body.village.training.at(-1).completesAt);
    await tick(db, now, scheduler);
    await call('POST', `/v1/villages/${home.id}/train`, mila.token, { unit: 'settler', count: 2 });
    now = new Date(now.getTime() + 3_600_000);
    await tick(db, now, scheduler);
    // Not on an ancient site or a camp, where no village can be founded.
    const camps = new Set((await call('GET', `/v1/worlds/${worldId}`, mila.token)).body.camps.map((c: { q: number; r: number }) => `${c.q},${c.r}`));
    const other = (started.body.map.hexes as [number, number, string][]).find(
      ([q, r, t]) =>
        settleable.has(t) &&
        hexDistance(hex(q, r), homeCell) >= 3 &&
        hexDistance(hex(q, r), homeCell) <= 6 &&
        hexDistance(hex(q, r), hex(site[0], site[1])) >= 4 &&
        hexDistance(hex(q, r), hex(0, 0)) >= 3 &&
        !ancient.has(`${q},${r}`) &&
        !camps.has(`${q},${r}`),
    )!;
    const doomed = await found(other[0], other[1]);
    expect(doomed.status).toBe(200);
    await db.query(`UPDATE villages SET q = $2, r = $3 WHERE id = $1`, [second.id, other[0], other[1] + 1]);
    now = new Date(doomed.body.expedition.arrivesAt);
    await tick(db, now, scheduler);
    world = (await call('GET', `/v1/worlds/${worldId}`, mila.token)).body;
    expect(world.expeditions[0]).toMatchObject({ status: 'returning', failure: expect.stringMatching(/apart/) });
    now = new Date(doomed.body.expedition.returnsAt);
    await tick(db, now, scheduler);
    world = (await call('GET', `/v1/worlds/${worldId}`, mila.token)).body;
    expect(world.villages.find((v: { id: number }) => v.id === home.id).away.settler ?? 0).toBe(0);
    expect(world.expeditions[0].status).toBe('done');
  });

  it('researches in the Academy; a finished tech helps every village of its player', async () => {
    const jarik = await guest('Jarik');
    const created = await call('POST', '/v1/worlds', jarik.token, { name: 'Research', maxPlayers: 1, speed: 10 });
    const worldId: number = created.body.id;
    await call('PUT', `/v1/worlds/${worldId}/hero`, jarik.token, { kind: 'dobrynya' });
    const started = await call('POST', `/v1/worlds/${worldId}/start`, jarik.token);
    const village = started.body.villages[0];
    const research = (tech: string) => call('POST', `/v1/villages/${village.id}/research`, jarik.token, { tech });
    await db.query(`UPDATE villages SET amounts = '{"wood": 900, "stone": 900, "grain": 900, "iron": 900}' WHERE id = $1`, [village.id]);

    expect((await research('felling_axes')).body.message).toMatch(/Academy of level 1/);
    const academy = await call('POST', `/v1/villages/${village.id}/build`, jarik.token, { building: 'academy' });
    now = new Date(academy.body.village.queue[0].completesAt);
    await tick(db, now, scheduler);

    expect((await research('shield_wall')).body.message).toMatch(/Academy of level 2/);
    const started1 = await research('felling_axes');
    expect(started1.status).toBe(200);
    expect(started1.body.research).toMatchObject({ accountId: jarik.accountId, tech: 'felling_axes', status: 'researching' });
    expect((await research('spear_drill')).body.message).toMatch(/one tech at a time/);
    const woodBefore = started1.body.village.resources.ratesPerHour.wood;

    now = new Date(started1.body.research.completesAt);
    await tick(db, now, scheduler);
    const world = (await call('GET', `/v1/worlds/${worldId}`, jarik.token)).body;
    expect(world.research).toEqual([expect.objectContaining({ accountId: jarik.accountId, tech: 'felling_axes', status: 'done' })]);
    // The tech, besides what Dobrynya brings to all of Jarik's villages.
    expect(world.villages[0].bonuses).toEqual({ ...rosterBonuses(scheduler.data, 'dobrynya'), 'production.wood': 0.1 });
    expect(world.villages[0].resources.ratesPerHour.wood).toBeCloseTo(woodBefore * 1.1);
    expect((await research('felling_axes')).body.message).toMatch(/already known/);
  });

  it('gives each player a hero who levels up, wears gear, travels and gets wounded', async () => {
    const rada = await guest('Rada');
    const created = await call('POST', '/v1/worlds', rada.token, { name: 'Heroes', maxPlayers: 1, speed: 10 });
    const worldId: number = created.body.id;
    // Dobrynya learns at the usual pace.
    await call('PUT', `/v1/worlds/${worldId}/hero`, rada.token, { kind: 'dobrynya' });
    const started = await call('POST', `/v1/worlds/${worldId}/start`, rada.token);
    const village = started.body.villages[0];
    expect(started.body.heroes).toEqual([
      expect.objectContaining({ accountId: rada.accountId, status: 'home', villageId: village.id, level: 1, skillPoints: 0 }),
    ]);
    const hero = (path: string, body: object) => call('POST', `/v1/worlds/${worldId}/hero/${path}`, rada.token, body);
    expect((await hero('rename', { name: 'Vasilisa' })).body.hero.name).toBe('Vasilisa');
    expect((await hero('skills', { skill: 'shield_bearer' })).body.message).toMatch(/No skill points/);
    expect((await hero('move', { villageId: village.id })).body.message).toMatch(/already there/);

    // A garrison led by the hero beats the first horde: XP, maybe gear.
    await db.query(`UPDATE villages SET garrison = '{"spearman": 60}' WHERE id = $1`, [village.id]);
    now = new Date(started.body.waves[0].spawnAt);
    await tick(db, now, scheduler);
    let world = (await call('GET', `/v1/worlds/${worldId}`, rada.token)).body;
    now = new Date(world.waves[0].arrivesAt);
    await tick(db, now, scheduler);
    for (let round = 0; round < 12; round++) {
      now = new Date(now.getTime() + (15 * 60_000) / 10);
      await tick(db, now, scheduler);
    }
    world = (await call('GET', `/v1/worlds/${worldId}`, rada.token)).body;
    expect(world.battles[0].status).toBe('defended');
    // The horde's leader, named for its front, fled wounded with a grudge,
    // or fell with the last of the horde.
    const front = world.battles[0].front;
    expect(world.leaders).toHaveLength(1);
    const chief = world.leaders[0];
    expect(world.battles[0].leaderId).toBe(chief.id);
    expect(chief).toMatchObject({ front, battles: 1, wins: 0, losses: 1 });
    expect(scheduler.data.leaders.fronts[front]!.names).toContain(chief.name);
    expect(chief.title).toContain(chief.name);
    const wiped = Object.values(world.battles[0].attackerNow as Record<string, number>).every((n) => n === 0);
    if (wiped) expect(chief).toMatchObject({ status: 'dead', grudgeVillageId: null });
    else expect(chief).toMatchObject({ status: 'alive', grudgeVillageId: village.id, woundedUntil: expect.any(String) });
    const veteran = world.heroes[0];
    const kills = Object.values(world.battles[0].attackerInitial as Record<string, number>).reduce((a, b) => a + b, 0)
      - Object.values(world.battles[0].attackerNow as Record<string, number>).reduce((a, b) => a + b, 0);
    expect(veteran.level > 1 || veteran.xp === kills).toBe(true);
    expect(veteran.status).toBe('home');

    // Skills and gear.
    await db.query(`UPDATE heroes SET skill_points = 2, inventory = '["bear_cloak", "bear_tooth"]' WHERE world_id = $1`, [worldId]);
    expect((await hero('skills', { skill: 'shield_bearer' })).body.hero.skills).toEqual({ shield_bearer: 1 });
    await hero('equip', { item: 'bear_cloak' });
    const geared = (await hero('equip', { item: 'bear_tooth' })).body.hero;
    expect(geared.gear).toEqual({ armor: 'bear_cloak', amulet: 'bear_tooth' });
    expect(geared.bonuses['defense.all']).toBeCloseTo(0.04 + 0.08 + 0.05);
    expect((await hero('unequip', { slot: 'mount' })).body.message).toMatch(/Nothing in that slot/);

    // Travel to a second village of hers, on open ground a few hexes away.
    const home = hex(village.q, village.r);
    const hexes = started.body.map.hexes as [number, number, TerrainId][];
    const terrain = new Map(hexes.map(([q, r, t]) => [`${q},${r}`, t]));
    const site = hexes.find(([q, r, t]) => {
      if (!['plains', 'forest', 'hills'].includes(t) || hexDistance(hex(q, r), home) !== 4) return false;
      try {
        return roadRoute(scheduler.data, terrain, home, hex(q, r), 6, 1).length > 0;
      } catch {
        return false;
      }
    })!;
    const { rows } = await db.query<{ id: number }>(
      `INSERT INTO villages (world_id, owner_account_id, name, q, r, levels, amounts, rates_per_hour, capacity, settled_at, queue, garrison, training, away, plots)
       SELECT world_id, owner_account_id, 'Second', $2, $3, levels, amounts, rates_per_hour, capacity, settled_at, '[]', '{}', '[]', '{}', plots
       FROM villages WHERE id = $1 RETURNING id`,
      [village.id, site[0], site[1]],
    );
    const second = rows[0]!.id;
    const moving = (await hero('move', { villageId: second })).body.hero;
    expect(moving).toMatchObject({ status: 'traveling', villageId: second });
    expect((await hero('move', { villageId: village.id })).body.message).toMatch(/already on the road/);
    now = new Date(moving.arrivesAt);
    await tick(db, now, scheduler);
    world = (await call('GET', `/v1/worlds/${worldId}`, rada.token)).body;
    expect(world.heroes[0]).toMatchObject({ status: 'home', villageId: second, path: null });

    // Raided with the hero at hand: wounded, then healed.
    await db.query(`UPDATE villages SET garrison = '{}' WHERE id = $1`, [second]);
    const next = world.waves.find((w: { status: string }) => w.status === 'scheduled');
    now = new Date(next.spawnAt);
    await tick(db, now, scheduler);
    // Whichever village it marched on, make it strike hers.
    const { rows: marching } = await db.query<{ arrives_at: Date }>(
      `UPDATE waves SET target_village_id = $2 WHERE id = $1 RETURNING arrives_at`,
      [next.id, second],
    );
    now = new Date(marching[0]!.arrives_at);
    await tick(db, now, scheduler);
    now = new Date(now.getTime() + (15 * 60_000) / 10);
    await tick(db, now, scheduler);
    world = (await call('GET', `/v1/worlds/${worldId}`, rada.token)).body;
    expect(world.battles[0]).toMatchObject({ villageId: second, status: 'raided' });
    expect(world.heroes[0].status).toBe('wounded');
    expect((await hero('move', { villageId: village.id })).body.message).toMatch(/wounded/);
    now = new Date(world.heroes[0].woundedUntil);
    await tick(db, now, scheduler);
    world = (await call('GET', `/v1/worlds/${worldId}`, rada.token)).body;
    expect(world.heroes[0]).toMatchObject({ status: 'home', woundedUntil: null });
  });

  it('runs standing orders: repeat training, rebuilding raided outposts, surplus to the vault', async () => {
    const lada = await guest('Ivo');
    const created = await call('POST', '/v1/worlds', lada.token, { name: 'Orders', maxPlayers: 1, speed: 10 });
    const worldId: number = created.body.id;
    const started = await call('POST', `/v1/worlds/${worldId}/start`, lada.token);
    const village = started.body.villages[0];
    const order = (body: object) => call('POST', `/v1/villages/${village.id}/orders`, lada.token, body);
    const world = async () => (await call('GET', `/v1/worlds/${worldId}`, lada.token)).body;
    const checkMs = (scheduler.data.orders.checkMinutes * 60_000) / 10;

    // Repeat training: waits for a barracks, then keeps 8 spearmen, 3 at a time.
    const train = await order({ kind: 'train', unit: 'spearman', batch: 3, target: 8 });
    expect(train.body.order).toMatchObject({ kind: 'train', unit: 'spearman', lastResult: expect.stringMatching(/Waiting: Spearman needs Barracks/) });
    expect((await order({ kind: 'train', unit: 'spearman', batch: 2, target: 4 })).body.message).toMatch(/already has that order/);
    const barracks = await call('POST', `/v1/villages/${village.id}/build`, lada.token, { building: 'barracks' });
    now = new Date(barracks.body.village.queue[0].completesAt);
    await tick(db, now, scheduler);
    await db.query(
      `UPDATE villages SET amounts = '{"wood": 900, "stone": 900, "grain": 900, "iron": 900}', settled_at = $2 WHERE id = $1`,
      [village.id, now],
    );
    for (let i = 0; i < 6; i++) {
      now = new Date(now.getTime() + checkMs);
      await tick(db, now, scheduler);
    }
    let w = await world();
    const fed = (w.villages[0].garrison.spearman ?? 0) + w.villages[0].training.reduce((n: number, b: { count: number }) => n + b.count, 0);
    expect(fed).toBe(8);
    expect(w.orders[0].lastResult).toMatch(/8 Spearman kept|Training/);

    // Surplus: everything above 50% of storage goes to the vault.
    const yard = await call('POST', `/v1/villages/${village.id}/build`, lada.token, { building: 'caravan_yard' });
    now = new Date(yard.body.village.queue.at(-1).completesAt);
    await tick(db, now, scheduler);
    await db.query(
      `UPDATE villages SET amounts = '{"wood": 900, "stone": 200, "grain": 200, "iron": 200}', settled_at = $2 WHERE id = $1`,
      [village.id, now],
    );
    const surplus = await order({ kind: 'surplus', share: 0.5 });
    expect(surplus.body.order.lastResult).toMatch(/Sent \d+ to the vault/);
    w = await world();
    const trip = w.caravans.find((c: { destinationVillageId: number | null; status: string }) => c.destinationVillageId === null && c.status === 'outbound');
    expect(trip.cargo.wood).toBeGreaterThan(350);

    // Rebuild: a raided outpost goes back up to its best level.
    await db.query(
      `UPDATE villages SET plots = plots || jsonb_build_object('o9,9', jsonb_build_object('building', 'outpost', 'level', 0, 'terrain', 'plains', 'peak', 1)),
         amounts = '{"wood": 900, "stone": 900, "grain": 900, "iron": 900}', settled_at = $2 WHERE id = $1`,
      [village.id, now],
    );
    const rebuild = await order({ kind: 'rebuild' });
    expect(rebuild.body.order.lastResult).toBe('Rebuilding the outpost at (9, 9)');
    expect(rebuild.body.village.queue.some((q: { plot: string }) => q.plot === 'o9,9')).toBe(true);

    // Two raided outposts and only enough for one: the first keeps its place in the queue.
    const cost = scheduler.data.buildings.buildings.outpost!.cost;
    await db.query(
      `UPDATE villages SET plots = plots || jsonb_build_object(
           'o9,10', jsonb_build_object('building', 'outpost', 'level', 0, 'terrain', 'plains', 'peak', 1),
           'o9,11', jsonb_build_object('building', 'outpost', 'level', 0, 'terrain', 'plains', 'peak', 1)),
         queue = '[]', amounts = $3, settled_at = $2 WHERE id = $1`,
      [village.id, now, JSON.stringify({ wood: cost.wood + 10, stone: cost.stone + 10, grain: cost.grain + 10, iron: cost.iron + 10 })],
    );
    await db.query(`UPDATE villages SET plots = plots - 'o9,9' WHERE id = $1`, [village.id]);
    // Placed again, so it runs now.
    await call('POST', `/v1/villages/${village.id}/orders/${rebuild.body.order.id}/cancel`, lada.token);
    const partial = await order({ kind: 'rebuild' });
    expect(partial.body.order.lastResult).toBe('Rebuilding the outpost at (9, 10)');
    expect(partial.body.village.queue.map((q: { plot: string }) => q.plot)).toEqual(['o9,10']);

    // Cancelled orders stop.
    const cancel = await call('POST', `/v1/villages/${village.id}/orders/${train.body.order.id}/cancel`, lada.token);
    expect(cancel.status).toBe(200);
    const left = (await world()).orders;
    expect(left.map((o: { kind: string }) => o.kind).sort()).toEqual(['rebuild', 'surplus']);
    // Stop the rest too: later tests move the clock days ahead, and every
    // world in the schema catches up on each tick.
    for (const o of left) await call('POST', `/v1/villages/${village.id}/orders/${o.id}/cancel`, lada.token);
  });

  it('tells players what happened: pushes for danger, a daily digest for the rest', async () => {
    const mira = await guest('Mira');
    const created = await call('POST', '/v1/worlds', mira.token, { name: 'Notices', maxPlayers: 1, speed: 10 });
    const worldId: number = created.body.id;
    const started = await call('POST', `/v1/worlds/${worldId}/start`, mira.token);
    const village = started.body.villages[0];
    const inbox = async () => (await call('GET', `/v1/worlds/${worldId}/notifications`, mira.token)).body;

    // Preferences and a device.
    const prefs = await call('PATCH', '/v1/me/notifications', mira.token, { quietStart: 1320, quietEnd: 420, digestHour: 20 });
    expect(prefs.body.prefs).toEqual({ quietStart: 1320, quietEnd: 420, utcOffsetMinutes: 0, digestHour: 20 });
    expect((await call('POST', '/v1/me/devices', mira.token, { token: 'phone-token-123', platform: 'android' })).status).toBe(200);

    // A small build goes to the digest (its getting-started notice is not what this test is about).
    await db.query(`UPDATE world_members SET onboarding = '{"build": "done"}' WHERE world_id = $1`, [worldId]);
    const build = await call('POST', `/v1/villages/${village.id}/build`, mira.token, { plot: 'f0' });
    now = new Date(build.body.village.queue[0].completesAt);
    await tick(db, now, scheduler);
    let box = await inbox();
    expect(box.notifications[0]).toMatchObject({ kind: 'build_done', tier: 'digest', read: false });
    expect(box.unread).toBe(1);

    // The horde: a warning, then the attack, both pushed.
    now = new Date(started.body.waves[0].spawnAt);
    await tick(db, now, scheduler);
    const wave = (await call('GET', `/v1/worlds/${worldId}`, mira.token)).body.waves[0];
    now = new Date(wave.arrivesAt);
    await tick(db, now, scheduler);
    box = await inbox();
    const kinds = box.notifications.map((n: { kind: string }) => n.kind);
    expect(kinds).toContain('wave_soon');
    expect(kinds).toContain('under_attack');
    expect(box.notifications.find((n: { kind: string }) => n.kind === 'wave_soon').title).toMatch(/A horde is coming to/);

    // Pushes go to the phone, except in quiet hours.
    const sent: string[] = [];
    const sender = { send: async (tokens: readonly string[], message: { title: string }) => (sent.push(`${tokens[0]}: ${message.title}`), []) };
    const noon = new Date('2026-07-01T12:00:00Z');
    // Older tests' notifications are long sent; only hers are pending.
    await db.query(`UPDATE notifications SET pushed_at = now() WHERE account_id <> $1`, [mira.accountId]);
    await db.query(`UPDATE notifications SET created_at = $1 WHERE account_id = $2`, [new Date(noon.getTime() - 60_000), mira.accountId]);
    expect(await pushPending(db, scheduler.data, null, new Date('2026-07-01T23:00:00Z'))).toBe(0);
    await db.query(`UPDATE notifications SET pushed_at = NULL WHERE account_id = $1`, [mira.accountId]);
    expect(await pushPending(db, scheduler.data, sender, new Date('2026-07-01T23:00:00Z'))).toBe(0);
    expect(await pushPending(db, scheduler.data, sender, noon)).toBeGreaterThanOrEqual(2);
    expect(sent.some((line) => line.startsWith('phone-token-123: A horde is coming'))).toBe(true);
    expect(sent.some((line) => /build/i.test(line))).toBe(false);

    // The digest at 20:00 sums up the rest.
    const { rows } = await db.query<{ due_at: Date }>(
      `SELECT due_at FROM scheduled_events WHERE world_id = $1 AND type = 'daily_digest' AND status = 'pending'`,
      [worldId],
    );
    expect(rows).toHaveLength(1);
    // After the first one, digests come at her digest hour (20:00).
    expect(rows[0]!.due_at.getUTCHours()).toBe(20);
    now = new Date(Math.max(rows[0]!.due_at.getTime(), now.getTime()));
    await tick(db, now, scheduler);
    box = await inbox();
    const digests = box.notifications.filter((n: { kind: string }) => n.kind === 'digest');
    expect(digests[0]).toMatchObject({ tier: 'push', title: 'Today in Notices' });
    expect(digests.some((d: { body: string }) => /1 build finished/.test(d.body))).toBe(true);
    const { rows: left } = await db.query(
      `SELECT 1 FROM notifications WHERE account_id = $1 AND tier = 'digest' AND digest_id IS NULL AND created_at <= $2`,
      [mira.accountId, now],
    );
    expect(left).toHaveLength(0);

    expect((await call('POST', `/v1/worlds/${worldId}/notifications/read`, mira.token)).status).toBe(200);
    expect((await inbox()).unread).toBe(0);
  });

  it('sends armies: support that guards an ally, reinforcements that rally to battles', async () => {
    const vid = await guest('Vid');
    const ola = await guest('Ola');
    const created = await call('POST', '/v1/worlds', vid.token, { name: 'Armies', maxPlayers: 2, speed: 10 });
    const worldId: number = created.body.id;
    await call('POST', '/v1/worlds/join', ola.token, { inviteCode: created.body.inviteCode });
    const started = await call('POST', `/v1/worlds/${worldId}/start`, vid.token);
    const a = started.body.villages.find((v: { ownerAccountId: number }) => v.ownerAccountId === vid.accountId);
    const b = started.body.villages.find((v: { ownerAccountId: number }) => v.ownerAccountId === ola.accountId);
    const world = async () => (await call('GET', `/v1/worlds/${worldId}`, vid.token)).body;
    const village = async (id: number) => (await world()).villages.find((v: { id: number }) => v.id === id);
    const roundMs = (15 * 60_000) / 10;
    await db.query(`UPDATE villages SET garrison = '{"spearman": 30}' WHERE id = $1`, [a.id]);
    await db.query(`UPDATE villages SET garrison = '{"spearman": 10, "archer": 10}' WHERE id = $1`, [b.id]);
    expect(a.reinforce).toEqual({ share: 0.5, range: 4 });
    expect((await call('PUT', `/v1/villages/${a.id}/reinforce`, vid.token, { share: 0, range: 4 })).status).toBe(200);
    expect((await call('PUT', `/v1/villages/${a.id}/reinforce`, ola.token, { share: 0, range: 4 })).status).toBe(403);

    // Vid sends 20 spearmen to stand guard at Ola's village.
    const send = (body: object) => call('POST', `/v1/villages/${a.id}/armies`, vid.token, body);
    expect((await send({ targetVillageId: b.id, units: { scout: 1 }, orders: 'support' })).body.message).toMatch(/don't march/);
    expect((await send({ targetVillageId: a.id, units: { spearman: 1 }, orders: 'support' })).body.message).toMatch(/another village/);
    expect((await send({ targetVillageId: b.id, units: { spearman: 99 }, orders: 'support' })).body.message).toMatch(/Only 30/);
    const sent = await send({ targetVillageId: b.id, units: { spearman: 20 }, orders: 'support' });
    expect(sent.body.army).toMatchObject({ status: 'marching', orders: 'support', units: { spearman: 20 } });
    expect((await village(a.id)).away.spearman).toBe(20);
    now = new Date(sent.body.army.arrivesAt);
    await tick(db, now, scheduler);
    expect((await world()).armies[0]).toMatchObject({ id: sent.body.army.id, status: 'stationed' });

    // A horde strikes Ola's village: the guard fights beside her garrison.
    now = new Date(started.body.waves[0].spawnAt);
    await tick(db, now, scheduler);
    const { rows: first } = await db.query<{ arrives_at: Date }>(
      `UPDATE waves SET target_village_id = $2 WHERE id = $1 RETURNING arrives_at`,
      [started.body.waves[0].id, b.id],
    );
    now = new Date(first[0]!.arrives_at);
    await tick(db, now, scheduler);
    let w = await world();
    expect(w.battles[0]).toMatchObject({ villageId: b.id, defenderInitial: { spearman: 30, archer: 10 } });
    expect(w.armies.find((x: { id: number }) => x.id === sent.body.army.id).status).toBe('engaged');
    for (let i = 0; i < 12 && (await world()).battles[0].status === 'ongoing'; i++) {
      now = new Date(now.getTime() + roundMs);
      await tick(db, now, scheduler);
    }
    w = await world();
    const guard = w.armies.find((x: { id: number }) => x.id === sent.body.army.id);
    expect(['stationed', 'done']).toContain(guard.status);
    if (guard.status === 'stationed') {
      const recalled = await call('POST', `/v1/armies/${guard.id}/recall`, vid.token);
      expect(recalled.body.army.status).toBe('returning');
      expect((await call('POST', `/v1/armies/${guard.id}/recall`, vid.token)).body.message).toMatch(/standing guard/);
      now = new Date(recalled.body.army.returnsAt);
      await tick(db, now, scheduler);
      const home = await village(a.id);
      expect(home.away.spearman ?? 0).toBe(0);
      expect(home.garrison.spearman).toBe(10 + guard.units.spearman);
    }

    // Next horde hits Vid: Ola's village sends half its troops (auto-reinforce).
    await call('PUT', `/v1/villages/${b.id}/reinforce`, ola.token, { share: 0.5, range: 8 });
    await db.query(`UPDATE villages SET garrison = '{"spearman": 20}' WHERE id = $1`, [b.id]);
    await db.query(`UPDATE villages SET garrison = '{"spearman": 30}' WHERE id = $1`, [a.id]);
    const second = (await world()).waves.find((x: { status: string }) => x.status === 'scheduled');
    now = new Date(second.spawnAt);
    await tick(db, now, scheduler);
    const { rows: next } = await db.query<{ arrives_at: Date }>(
      `UPDATE waves SET target_village_id = $2, composition = '{"grey_wolf": 60}' WHERE id = $1 RETURNING arrives_at`,
      [second.id, a.id],
    );
    now = new Date(next[0]!.arrives_at);
    await tick(db, now, scheduler);
    w = await world();
    const help = w.armies.find((x: { homeVillageId: number; status: string }) => x.homeVillageId === b.id && x.status === 'marching');
    expect(help).toMatchObject({ orders: 'reinforce', targetVillageId: a.id, units: { spearman: 10 } });
    // Let it arrive in time for the first round.
    await db.query(`UPDATE scheduled_events SET due_at = $2 WHERE type = 'army_arrive' AND payload @> $1::jsonb AND status = 'pending'`, [
      JSON.stringify({ armyId: help.id }),
      new Date(now.getTime() + 1),
    ]);
    now = new Date(now.getTime() + roundMs);
    await tick(db, now, scheduler);
    w = await world();
    const battle = w.battles.find((x: { villageId: number }) => x.villageId === a.id);
    expect(battle.rounds[0].joined).toEqual([expect.objectContaining({ armyId: help.id, villageId: b.id, orders: 'reinforce' })]);
    expect(battle.defenderInitial.spearman).toBe(40);
    for (let i = 0; i < 12 && battle.status === 'ongoing' && (await world()).battles.find((x: { id: number }) => x.id === battle.id).status === 'ongoing'; i++) {
      now = new Date(now.getTime() + roundMs);
      await tick(db, now, scheduler);
    }
    const after = (await world()).armies.find((x: { id: number }) => x.id === help.id);
    expect(['returning', 'done']).toContain(after.status);
  });

  it('holds a hex: field battles with a fort and a hero, and a horde that breaks through', async () => {
    const mira = await guest('Mira');
    const created = await call('POST', '/v1/worlds', mira.token, { name: 'Field', maxPlayers: 1, speed: 10 });
    const worldId: number = created.body.id;
    const started = await call('POST', `/v1/worlds/${worldId}/start`, mira.token);
    const home = started.body.villages[0];
    const world = async () => (await call('GET', `/v1/worlds/${worldId}`, mira.token)).body;
    const roundMs = (15 * 60_000) / 10;
    const terrain = new Map<string, TerrainId>(started.body.map.hexes.map(([q, r, t]: [number, number, TerrainId]) => [`${q},${r}`, t]));
    await db.query(`UPDATE villages SET garrison = '{"spearman": 400, "archer": 200}', amounts = '{"wood": 5000, "stone": 5000, "grain": 5000, "iron": 5000}' WHERE id = $1`, [home.id]);

    // The first horde sets out; Mira picks a hex on its road two steps short of her village.
    const first = started.body.waves[0];
    now = new Date(first.spawnAt);
    await tick(db, now, scheduler);
    const marching = (await world()).waves.find((x: { id: number }) => x.id === first.id);
    // A hex on the road a few steps short of the village: in fort range,
    // not the Holy City (no forts there).
    // (and no ancient site)
    const ancient = new Set(started.body.sites.map((s: { q: number; r: number }) => `${s.q},${s.r}`));
    const holdable = (path: [number, number, number][]) =>
      path.slice(0, -1).reverse().find(([pq, pr]) => {
        const d = hexDistance(hex(pq, pr), hex(home.q, home.r));
        return d >= 2 && d <= 4 && (pq !== 0 || pr !== 0) && !ancient.has(`${pq},${pr}`);
      })!;
    const [q, r, atMs] = holdable(marching.path);
    const meetAt = new Date(new Date(marching.spawnAt).getTime() + atMs);

    // A fort first: not on the village, not too far, then on the hex.
    const fort = (body: object) => call('POST', `/v1/villages/${home.id}/forts`, mira.token, body);
    expect((await fort({ q: home.q, r: home.r })).body.message).toMatch(/within/);
    expect((await fort({ q: home.q + 9, r: home.r })).body.message).toMatch(/within/);
    const built = await fort({ q, r });
    expect(built.body.fort).toMatchObject({ q, r, status: 'building' });
    expect((await fort({ q, r })).body.message).toMatch(/already/);
    const cost = scheduler.data.field.fort.cost;
    const village = (await world()).villages[0];
    expect(village.resources.amounts.stone).toBeLessThanOrEqual(5000 - cost.stone + 1);

    // The hold army, led by Mira's hero.
    const send = (body: object) => call('POST', `/v1/villages/${home.id}/armies`, mira.token, body);
    expect((await send({ units: { spearman: 1 }, orders: 'hold' })).body.message).toMatch(/which hex/);
    const held = await send({ target: { q, r }, units: { spearman: 300, archer: 150 }, orders: 'hold', withHero: true });
    expect(held.body.army).toMatchObject({ status: 'marching', orders: 'hold', target: [q, r], targetVillageId: null });
    let w = await world();
    expect(w.heroes[0]).toMatchObject({ status: 'with_army' });
    // Let the army dig in well before the horde (time for an ambush) and the fort finish.
    const early = new Date(now.getTime() + 1);
    await db.query(`UPDATE armies SET arrives_at = $2 WHERE id = $1`, [held.body.army.id, early]);
    await db.query(`UPDATE scheduled_events SET due_at = $2 WHERE type IN ('army_arrive', 'fort_complete') AND status = 'pending' AND world_id = $1`, [worldId, early]);
    now = early;
    await tick(db, now, scheduler);
    w = await world();
    expect(w.armies[0].status).toBe('stationed');
    expect(w.forts[0]).toMatchObject({ q, r, status: 'standing' });
    const xpBefore = w.heroes[0].xp;
    // The Iron Span is being built: holding the fort answers its strong-point quest.
    const ironSpan = scheduler.data.bridge.stages.findIndex((s) => s.quests.some((x) => x.kind === 'choke'));
    await db.query(`UPDATE bridges SET state = state || jsonb_build_object('stage', $2::int) WHERE world_id = $1`, [worldId, ironSpan]);

    now = meetAt;
    await tick(db, now, scheduler);
    w = await world();
    let battle = w.battles[0];
    const cover = scheduler.data.field.ambush.terrain.includes(terrain.get(`${q},${r}`)!);
    expect(battle).toMatchObject({ villageId: null, q, r, status: 'ongoing', setup: { fort: true, ambush: cover } });
    expect(battle.defenderInitial).toEqual({ spearman: 300, archer: 150 });
    expect(w.waves.find((x: { id: number }) => x.id === first.id).status).toBe('battling');
    for (let i = 0; i < 12 && battle.status === 'ongoing'; i++) {
      now = new Date(now.getTime() + roundMs);
      await tick(db, now, scheduler);
      battle = (await world()).battles.find((x: { id: number }) => x.id === battle.id);
    }
    expect(battle.status).toBe('defended');
    w = await world();
    expect(w.bridge.quests.choke).toBeTruthy();
    expect(w.waves.some((x: { id: number }) => x.id === first.id)).toBe(false);
    expect(w.armies[0].status).toBe('stationed');
    expect(w.heroes[0].status).toBe('with_army');
    expect(w.heroes[0].level > 1 || w.heroes[0].xp > xpBefore).toBe(true);
    // The village never saw a battle.
    expect(w.battles.filter((x: { villageId: number | null }) => x.villageId !== null)).toEqual([]);

    // Called home, the army brings the hero back.
    const recalled = await call('POST', `/v1/armies/${held.body.army.id}/recall`, mira.token);
    expect(recalled.body.army.status).toBe('returning');
    now = new Date(recalled.body.army.returnsAt);
    await tick(db, now, scheduler);
    w = await world();
    expect(w.heroes[0]).toMatchObject({ status: 'home', villageId: home.id });
    expect(w.villages[0].away.spearman ?? 0).toBe(0);

    // The next horde meets a lone spearman, breaks through, and reaches the village late.
    const second = w.waves.find((x: { status: string }) => x.status === 'scheduled');
    now = new Date(second.spawnAt);
    await tick(db, now, scheduler);
    await db.query('UPDATE waves SET target_village_id = $2 WHERE id = $1', [second.id, home.id]);
    const next = (await world()).waves.find((x: { id: number }) => x.id === second.id);
    const [q2, r2, atMs2] = holdable(next.path);
    const lone = await send({ target: { q: q2, r: r2 }, units: { spearman: 1 }, orders: 'hold' });
    await db.query(`UPDATE scheduled_events SET due_at = $2 WHERE type = 'army_arrive' AND status = 'pending' AND world_id = $1`, [worldId, new Date(now.getTime() + 1)]);
    now = new Date(new Date(next.spawnAt).getTime() + atMs2);
    await tick(db, now, scheduler);
    let fight = (await world()).battles.find((x: { q: number; r: number; status: string }) => x.q === q2 && x.r === r2 && x.status === 'ongoing');
    expect(fight).toBeTruthy();
    for (let i = 0; i < 12 && fight.status === 'ongoing'; i++) {
      now = new Date(now.getTime() + roundMs);
      await tick(db, now, scheduler);
      fight = (await world()).battles.find((x: { id: number }) => x.id === fight.id);
    }
    expect(fight.status).toBe('raided');
    w = await world();
    const late = w.waves.find((x: { id: number }) => x.id === second.id);
    expect(late.status).toBe('marching');
    expect(new Date(late.arrivesAt).getTime()).toBe(new Date(next.arrivesAt).getTime() + (now.getTime() - (new Date(next.spawnAt).getTime() + atMs2)));
    expect(['returning', 'done']).toContain(w.armies.find((x: { id: number }) => x.id === lone.body.army.id).status);
    // The old arrival time passes quietly; the new one starts the village battle.
    now = new Date(next.arrivesAt);
    await tick(db, now, scheduler);
    expect((await world()).battles.some((x: { villageId: number | null }) => x.villageId === home.id)).toBe(false);
    now = new Date(late.arrivesAt);
    await tick(db, now, scheduler);
    expect((await world()).battles.some((x: { villageId: number | null }) => x.villageId === home.id)).toBe(true);
  });

  it('hordes raid or raze, roam on, settle into camps and strike the Holy City', async () => {
    const lada = await guest('Lada');
    const created = await call('POST', '/v1/worlds', lada.token, { name: 'Horde', maxPlayers: 1, speed: 10 });
    const worldId: number = created.body.id;
    const started = await call('POST', `/v1/worlds/${worldId}/start`, lada.token);
    const home = started.body.villages[0];
    expect(started.body.sanctity).toBe(scheduler.data.horde.holyCity.sanctity);
    const world = async () => (await call('GET', `/v1/worlds/${worldId}`, lada.token)).body;
    const roundMs = (15 * 60_000) / 10;
    const fight = async (battleId: number) => {
      let battle = (await world()).battles.find((b: { id: number }) => b.id === battleId);
      for (let i = 0; i < 12 && battle.status === 'ongoing'; i++) {
        now = new Date(now.getTime() + roundMs);
        await tick(db, now, scheduler);
        battle = (await world()).battles.find((b: { id: number }) => b.id === battleId);
      }
      return battle;
    };

    // A later horde (past the early raiding parties) breaks the empty village and burns it.
    const first = started.body.waves[0];
    now = new Date(first.spawnAt);
    await tick(db, now, scheduler);
    // Monsters pick their target erratically: make sure it is the village, and
    // play a later wave (until it has decided).
    await db.query('UPDATE waves SET target_village_id = $2, index = 7 WHERE id = $1', [first.id, home.id]);
    now = new Date((await world()).waves.find((w: { id: number }) => w.id === first.id).arrivesAt);
    await tick(db, now, scheduler);
    let battle = await fight((await world()).battles[0].id);
    expect(battle).toMatchObject({ villageId: home.id, status: 'raided', loot: null, decision: { choice: 'raze' } });
    let wave = (await world()).waves.find((w: { id: number }) => w.id === first.id);
    expect(wave.status).toBe('razing');
    await db.query('UPDATE waves SET index = 0 WHERE id = $1', [first.id]);
    now = new Date(wave.endsAt);
    await tick(db, now, scheduler);
    let w = await world();
    const ruin = w.villages.find((v: { id: number }) => v.id === home.id);
    expect(ruin.ruin).toMatchObject({ since: now.toISOString(), rebuildingUntil: null });
    expect(ruin.plots.c0.level).toBe(0);
    // Nothing left standing: a refugee camp near the Holy City, which hordes never raze.
    const refuge = w.villages.find((v: { refuge: boolean }) => v.refuge);
    expect(refuge).toMatchObject({ ownerAccountId: lada.accountId });
    expect(Math.max(Math.abs(refuge.q), Math.abs(refuge.r), Math.abs(refuge.q + refuge.r))).toBeGreaterThanOrEqual(2);
    const moved = w.waves.find((x: { id: number }) => x.id === first.id);
    if (moved) expect(moved.struck).toEqual([home.id]);
    expect((await call('POST', `/v1/villages/${home.id}/build`, lada.token, { building: 'barracks' })).body.message).toMatch(/ruins/);

    // Rebuilding costs a share of what stood and takes a while.
    expect((await call('POST', `/v1/villages/${home.id}/rebuild`, lada.token)).body.message).toMatch(/Missing|Not enough|resources/i);
    await db.query(`UPDATE villages SET amounts = '{"wood": 9000, "stone": 9000, "grain": 9000, "iron": 9000}' WHERE id = $1`, [home.id]);
    const rebuilt = await call('POST', `/v1/villages/${home.id}/rebuild`, lada.token);
    expect(rebuilt.body.village.ruin.rebuildingUntil).toBeTruthy();
    expect((await call('POST', `/v1/villages/${home.id}/rebuild`, lada.token)).body.message).toMatch(/already/);
    now = new Date(rebuilt.body.village.ruin.rebuildingUntil);
    await tick(db, now, scheduler);
    const standing = (await world()).villages.find((v: { id: number }) => v.id === home.id);
    expect(standing.ruin).toBeNull();
    expect(standing.plots.c0.level).toBe(1);

    // Out of time on its rampage clock, a horde makes camp after its raid.
    w = await world();
    const second = w.waves.find((x: { status: string }) => x.status === 'scheduled');
    now = new Date(second.spawnAt);
    await tick(db, now, scheduler);
    await db.query('UPDATE waves SET target_village_id = $2 WHERE id = $1', [second.id, home.id]);
    const marching = (await world()).waves.find((x: { id: number }) => x.id === second.id);
    now = new Date(marching.arrivesAt);
    await tick(db, now, scheduler);
    await db.query('UPDATE waves SET rampage_ends_at = $2 WHERE id = $1', [second.id, now]);
    battle = await fight((await world()).battles.find((b: { waveId: number }) => b.waveId === second.id).id);
    expect(battle.decision).toEqual({ choice: 'raid', reasons: ['an early raiding party'] });
    w = await world();
    expect(w.waves.some((x: { id: number }) => x.id === second.id)).toBe(false);
    const settled = w.camps.filter((c: { waveId: number }) => c.waveId === second.id);
    expect(settled.length).toBeGreaterThanOrEqual(1);
    expect(settled[0]).toMatchObject({ front: second.front, kind: second.front === 'north' ? 'lair' : 'bandit' });
    expect(settled[0].size).toBeGreaterThan(0);

    // A horde at the Holy City fights its guard; winning costs Sanctity.
    const third = w.waves.find((x: { status: string }) => x.status === 'scheduled');
    now = new Date(third.spawnAt);
    await tick(db, now, scheduler);
    const { rows } = await db.query<{ arrives_at: Date }>(
      `UPDATE waves SET target_village_id = NULL, composition = '{"cave_bear": 400, "zealot": 400}' WHERE id = $1 RETURNING arrives_at`,
      [third.id],
    );
    now = new Date(rows[0]!.arrives_at);
    await tick(db, now, scheduler);
    w = await world();
    const siege = w.battles.find((b: { waveId: number }) => b.waveId === third.id);
    expect(siege).toMatchObject({ villageId: null, q: 0, r: 0, setup: { holyCity: true } });
    battle = await fight(siege.id);
    expect(battle.status).toBe('raided');
    w = await world();
    expect(w.sanctity).toBeLessThan(scheduler.data.horde.holyCity.sanctity);
  });

  it('camps rise after waves and grow, ambush caravans, fall to armies; empty forts turn bandit', async () => {
    const bogdan = await guest('Bogdan');
    const created = await call('POST', '/v1/worlds', bogdan.token, { name: 'Camps', maxPlayers: 1, speed: 10 });
    const worldId: number = created.body.id;
    const started = await call('POST', `/v1/worlds/${worldId}/start`, bogdan.token);
    const home = started.body.villages[0];
    const world = async () => (await call('GET', `/v1/worlds/${worldId}`, bogdan.token)).body;
    const village = async () => (await world()).villages.find((v: { id: number }) => v.id === home.id);
    const roundMs = (15 * 60_000) / 10;
    const hourMs = 3_600_000 / 10;
    await db.query(
      `UPDATE villages SET garrison = '{"spearman": 200, "archer": 120}', amounts = '{"wood": 5000, "stone": 5000, "grain": 5000, "iron": 5000}',
         plots = plots || '{"c1": {"building": "caravan_yard", "level": 3}}', levels = levels || '{"caravan_yard": 3}' WHERE id = $1`,
      [home.id],
    );

    // The garrison beats the first horde; a camp of its front rises near its road.
    const first = started.body.waves[0];
    now = new Date(first.spawnAt);
    await tick(db, now, scheduler);
    await db.query('UPDATE waves SET target_village_id = $2 WHERE id = $1', [first.id, home.id]);
    now = new Date((await world()).waves.find((w: { id: number }) => w.id === first.id).arrivesAt);
    await tick(db, now, scheduler);
    for (let i = 0; i < 12; i++) {
      now = new Date(now.getTime() + roundMs);
      await tick(db, now, scheduler);
    }
    let w = await world();
    expect(w.battles[0]).toMatchObject({ villageId: home.id, status: 'defended' });
    const camp = w.camps.find((c: { waveId: number }) => c.waveId === first.id);
    expect(camp).toMatchObject({ front: first.front, kind: first.front === 'north' ? 'lair' : 'bandit' });
    const size = camp.size;

    // A day later it has grown.
    now = new Date(now.getTime() + 24 * hourMs);
    await tick(db, now, scheduler);
    expect((await world()).camps.find((c: { id: number }) => c.id === camp.id).size).toBeGreaterThan(size);

    // A camp on the road to the Holy City robs an unguarded caravan; an escort beats it off.
    const terrain = new Map<string, TerrainId>(started.body.map.hexes.map(([q, r, t]: [number, number, TerrainId]) => [`${q},${r}`, t]));
    const road = roadRoute(scheduler.data, terrain, hex(home.q, home.r), hex(0, 0), scheduler.data.logistics.caravan.speed, 10);
    const mid = road[Math.floor(road.length / 2)]!;
    const { rows: bandits } = await db.query<{ id: number }>(
      `INSERT INTO camps (world_id, kind, front, q, r, units, created_at) VALUES ($1, 'bandit', 'south', $2, $3, '{"zealot": 12}', $4) RETURNING id`,
      [worldId, mid.q, mid.r, now],
    );
    const load = { wood: 400, stone: 0, grain: 0, iron: 0 };
    const send = (escort?: object) => call('POST', `/v1/villages/${home.id}/caravans`, bogdan.token, { destinationVillageId: null, load, ...(escort ? { escort } : {}) });
    const robbed = await send();
    const guarded = await send({ archer: 40 });
    expect(guarded.body.caravan.escort).toEqual({ archer: 40 });
    expect((await village()).away.archer).toBe(40);
    now = new Date(guarded.body.caravan.returnsAt);
    await tick(db, now, scheduler);
    w = await world();
    const trips = (id: number) => w.caravans.find((c: { id: number }) => c.id === id);
    expect(trips(robbed.body.caravan.id).ambush).toMatchObject({ campId: bandits[0]!.id, beatenOff: false, lost: { wood: 200 } });
    expect(trips(guarded.body.caravan.id).ambush).toMatchObject({ beatenOff: true, lost: { wood: 0 } });
    expect(w.vault.amounts.wood).toBe(600);
    expect((await village()).away.archer ?? 0).toBe(0);

    // An army clears the camp and carries its loot home.
    const target = w.camps.find((c: { id: number }) => c.id === camp.id);
    const army = await call('POST', `/v1/villages/${home.id}/armies`, bogdan.token, {
      target: { q: target.q, r: target.r },
      units: { spearman: 150, archer: 60 },
      orders: 'clear',
    });
    expect(army.body.army).toMatchObject({ orders: 'clear', target: [target.q, target.r] });
    expect((await call('POST', `/v1/villages/${home.id}/armies`, bogdan.token, { target: { q: home.q, r: home.r }, units: { spearman: 1 }, orders: 'clear' })).body.message).toMatch(/no camp/);
    now = new Date(army.body.army.arrivesAt);
    await tick(db, now, scheduler);
    w = await world();
    const storm = w.battles.find((b: { campId: number }) => b.campId === camp.id);
    expect(storm).toMatchObject({ status: 'cleared', waveId: null, q: target.q, r: target.r });
    expect(storm.loot.wood).toBeGreaterThan(0);
    expect(w.camps.some((c: { id: number }) => c.id === camp.id)).toBe(false);
    const marching = w.armies.find((a: { id: number }) => a.id === army.body.army.id);
    expect(marching).toMatchObject({ status: 'returning', loot: storm.loot });
    expect([0, 1]).toContain(w.embers);
    const before = (await village()).resources.amounts.iron;
    now = new Date(marching.returnsAt);
    await tick(db, now, scheduler);
    expect((await village()).resources.amounts.iron).toBeGreaterThanOrEqual(Math.min(before + storm.loot.iron, (await village()).resources.capacity.iron) - 1);

    // A fort nobody holds falls to bandits.
    const taken = new Set(w.camps.map((c: { q: number; r: number }) => `${c.q},${c.r}`));
    const [sq, sr] = [...terrain.entries()]
      .map(([key, t]) => [...key.split(',').map(Number), t] as [number, number, TerrainId])
      .find(([q, r, t]) => ['plains', 'forest', 'hills'].includes(t) && hexDistance(hex(q, r), hex(home.q, home.r)) === 2 && !taken.has(`${q},${r}`))!;
    const site = { q: sq, r: sr };
    await db.query(`UPDATE villages SET amounts = '{"wood": 5000, "stone": 5000, "grain": 5000, "iron": 5000}' WHERE id = $1`, [home.id]);
    const fort = await call('POST', `/v1/villages/${home.id}/forts`, bogdan.token, { q: site.q, r: site.r });
    expect(fort.body.fort.status).toBe('building');
    now = new Date(new Date(fort.body.fort.completesAt).getTime() + scheduler.data.camps.fort.abandonHours * hourMs + 1);
    await tick(db, now, scheduler);
    w = await world();
    expect(w.forts.some((f: { q: number; r: number }) => f.q === site.q && f.r === site.r)).toBe(false);
    expect(w.camps).toEqual(expect.arrayContaining([expect.objectContaining({ kind: 'bandit', q: site.q, r: site.r })]));
  });

  it('difficulty sets wave sizes; quiet hours set by the host hold hordes back', async () => {
    const yara = await guest('Yara');
    const stranger = await guest('Stranger');
    const created = await call('POST', '/v1/worlds', yara.token, { name: 'Gentle', maxPlayers: 1, speed: 10, difficulty: 'story' });
    expect(created.body.difficulty).toBe('story');
    expect((await call('POST', '/v1/worlds', yara.token, { name: 'Bad', difficulty: 'impossible' })).status).toBe(400);
    const worldId: number = created.body.id;
    const started = await call('POST', `/v1/worlds/${worldId}/start`, yara.token);
    const home = started.body.villages[0];
    // Story waves come at 70% of their base size.
    const { rows: sizes } = await db.query<{ composition: Record<string, number> }>('SELECT composition FROM waves WHERE world_id = $1 AND index = 0', [worldId]);
    expect(Object.values(sizes[0]!.composition).reduce((a, b) => a + b, 0)).toBe(Math.round(scheduler.data.waves.baseUnits * 0.7));

    // Quiet hours: nearly the whole day from the moment the first horde sets out.
    const first = started.body.waves[0];
    const spawnAt = new Date(first.spawnAt);
    const minute = spawnAt.getUTCHours() * 60 + spawnAt.getUTCMinutes();
    const quiet = { start: minute, end: (minute + 1439) % 1440, utcOffsetMinutes: 0 };
    expect((await call('PUT', `/v1/worlds/${worldId}/quiet`, stranger.token, quiet)).status).toBe(403);
    const set = await call('PUT', `/v1/worlds/${worldId}/quiet`, yara.token, quiet);
    expect(set.body.quietHours).toEqual(quiet);
    now = spawnAt;
    await tick(db, now, scheduler);
    const marching = (await call('GET', `/v1/worlds/${worldId}`, yara.token)).body.waves[0];
    const end = new Date(Math.floor(spawnAt.getTime() / 60_000) * 60_000 + 1439 * 60_000);
    expect(marching.arrivesAt).toBe(end.toISOString());
    expect(marching.path.at(-1)[2]).toBe(end.getTime() - spawnAt.getTime());
    // It waits outside until the window ends, then attacks.
    now = new Date(end.getTime() - 60_000);
    await tick(db, now, scheduler);
    expect((await call('GET', `/v1/worlds/${worldId}`, yara.token)).body.battles).toEqual([]);
    now = end;
    await tick(db, now, scheduler);
    expect((await call('GET', `/v1/worlds/${worldId}`, yara.token)).body.battles[0]).toMatchObject({ villageId: home.id });
    // Cleared quiet hours.
    expect((await call('PUT', `/v1/worlds/${worldId}/quiet`, yara.token, { start: null, end: null })).body.quietHours).toBeNull();
  });

  it('explores ancient sites: guardians, a search, and finds such as lore scrolls for the whole group', async () => {
    const vesna = await guest('Vesna');
    const ilya = await guest('Ilya');
    const created = await call('POST', '/v1/worlds', vesna.token, { name: 'Sites', maxPlayers: 2, speed: 10 });
    const worldId: number = created.body.id;
    await call('POST', '/v1/worlds/join', ilya.token, { inviteCode: created.body.inviteCode });
    const started = await call('POST', `/v1/worlds/${worldId}/start`, vesna.token);
    const home = started.body.villages.find((v: { ownerAccountId: number }) => v.ownerAccountId === vesna.accountId);
    const theirs = started.body.villages.find((v: { ownerAccountId: number }) => v.ownerAccountId === ilya.accountId);
    const world = async () => (await call('GET', `/v1/worlds/${worldId}`, vesna.token)).body;
    expect(started.body.sites.length).toBeGreaterThanOrEqual(scheduler.data.sites.placement.min);
    expect(started.body.sites.every((s: { status: string; guardians: null }) => s.status === 'unexplored' && s.guardians === null)).toBe(true);
    const [watched, idol] = started.body.sites as { id: number; q: number; r: number; kind: string }[];
    await db.query(`UPDATE sites SET guardians = '{"cave_bear": 30}' WHERE id = $1`, [watched!.id]);
    await db.query(`UPDATE sites SET guardians = '{"grey_wolf": 3}', kind = 'stone_idol' WHERE id = $1`, [idol!.id]);
    await db.query(`UPDATE villages SET garrison = '{"spearman": 80, "scout": 6}' WHERE id = $1`, [home.id]);
    const send = (target: { q: number; r: number }, units: object, extra: object = {}) =>
      call('POST', `/v1/villages/${home.id}/armies`, vesna.token, { target: { q: target.q, r: target.r }, units, orders: 'explore', ...extra });
    expect((await send({ q: home.q, r: home.r }, { scout: 1 })).body.message).toMatch(/no ancient site/);

    // Scouts alone can't get past the bears; now the group knows they are there.
    const scouts = await send(watched!, { scout: 4 });
    expect(scouts.body.army).toMatchObject({ orders: 'explore', units: { scout: 4 } });
    now = new Date(scouts.body.army.arrivesAt);
    await tick(db, now, scheduler);
    let w = await world();
    expect(w.battles.find((b: { siteId: number }) => b.siteId === watched!.id)).toMatchObject({ status: 'repelled' });
    expect(w.sites.find((s: { id: number }) => s.id === watched!.id)).toMatchObject({ status: 'unexplored', guardians: 30 });

    // An army led by the hero beats the wolves at the idol, searches it and finds a scroll.
    const finds = scheduler.data.sites.kinds.stone_idol!.finds;
    const saved = { ...finds };
    Object.assign(finds, { resources: 0, gear: 0, scroll: 1, ember: 0 });
    try {
      const army = await send(idol!, { spearman: 40, scout: 2 }, { withHero: true });
      now = new Date(army.body.army.arrivesAt);
      await tick(db, now, scheduler);
      w = await world();
      expect(w.battles.find((b: { siteId: number }) => b.siteId === idol!.id)).toMatchObject({ status: 'cleared' });
      expect(w.armies.find((a: { id: number }) => a.id === army.body.army.id).status).toBe('stationed');
      now = new Date(now.getTime() + (scheduler.data.sites.kinds.stone_idol!.exploreHours * 3_600_000) / 10);
      await tick(db, now, scheduler);
      w = await world();
      const site = w.sites.find((s: { id: number }) => s.id === idol!.id);
      expect(site).toMatchObject({ status: 'explored', exploredBy: vesna.accountId, find: { type: 'scroll' } });
      expect(w.lore).toEqual([expect.objectContaining({ scroll: site.find.scroll, accountId: vesna.accountId, siteId: idol!.id })]);
      // Its effects reach every player's villages, not just the finder's.
      const effects = scheduler.data.lore.scrolls[site.find.scroll]!.effects;
      for (const v of [home, theirs]) {
        const village = w.villages.find((x: { id: number }) => x.id === v.id);
        // On top of what each player's roster hero brings.
        const kind = w.members.find((m: { accountId: number }) => m.accountId === village.ownerAccountId).heroKind;
        for (const [key, value] of Object.entries(effects)) expect(village.bonuses[key]).toBeCloseTo(value + (rosterBonuses(scheduler.data, kind)[key] ?? 0));
      }
      expect(w.armies.find((a: { id: number }) => a.id === army.body.army.id).status).toBe('returning');
      expect((await send(idol!, { scout: 1 })).body.message).toMatch(/already been explored/);
    } finally {
      Object.assign(finds, saved);
    }
  });

  it('builds the Kalinov Bridge from the vault, with quests, stage by stage', async () => {
    const rusa = await guest('Rusa');
    const created = await call('POST', '/v1/worlds', rusa.token, { name: 'Bridge', maxPlayers: 1, speed: 10 });
    const worldId: number = created.body.id;
    const started = await call('POST', `/v1/worlds/${worldId}/start`, rusa.token);
    const home = started.body.villages[0];
    const stage0 = scheduler.data.bridge.stages[0]!;
    expect(started.body.bridge).toMatchObject({ stage: 0, status: 'open', embers: 0, quests: {} });
    const donate = (resources: object, embers = 0) =>
      call('POST', `/v1/worlds/${worldId}/bridge/donate`, rusa.token, { resources: { wood: 0, stone: 0, grain: 0, iron: 0, ...resources }, embers });
    expect((await donate({ stone: 100 })).body.message).toMatch(/needs none/);
    expect((await call('POST', `/v1/worlds/${worldId}/bridge/ritual`, rusa.token)).body.message).toMatch(/No stage needs/);

    // Donations come out of the vault, as much as the stage needs.
    await db.query(`UPDATE vaults SET amounts = '{"wood": 3000, "stone": 3000, "grain": 3000, "iron": 3000}' WHERE world_id = $1`, [worldId]);
    let w = (await donate({ wood: 3000, stone: 3000, grain: 3000, iron: 3000 })).body;
    expect(w.bridge.donated).toEqual({ wood: stage0.cost.wood, stone: 3000, grain: stage0.cost.grain, iron: stage0.cost.iron });
    expect(w.vault.amounts).toEqual({ wood: 3000 - stage0.cost.wood, stone: 0, grain: 3000 - stage0.cost.grain, iron: 3000 - stage0.cost.iron });
    await db.query(`UPDATE vaults SET amounts = '{"wood": 0, "stone": 3000, "grain": 0, "iron": 0}' WHERE world_id = $1`, [worldId]);
    w = (await donate({ stone: 3000 })).body;
    expect(w.bridge.donated.stone).toBe(stage0.cost.stone);
    expect(w.bridge.status).toBe('open');

    // Its quest: bring back a relic from an ancient site.
    const site = started.body.sites[0];
    await db.query(`UPDATE sites SET guardians = '{}' WHERE id = $1`, [site.id]);
    await db.query(`UPDATE villages SET garrison = '{"scout": 3}' WHERE id = $1`, [home.id]);
    const scouts = await call('POST', `/v1/villages/${home.id}/armies`, rusa.token, { target: { q: site.q, r: site.r }, units: { scout: 3 }, orders: 'explore' });
    now = new Date(scouts.body.army.arrivesAt);
    await tick(db, now, scheduler);
    now = new Date(now.getTime() + (scheduler.data.sites.kinds[site.kind]!.exploreHours * 3_600_000) / 10);
    await tick(db, now, scheduler);
    w = (await call('GET', `/v1/worlds/${worldId}`, rusa.token)).body;
    expect(w.bridge.quests.site).toBe(now.toISOString());
    expect(w.bridge.status).toBe('raising');

    // Raised: the next stage opens.
    now = new Date(w.bridge.raisedAt);
    await tick(db, now, scheduler);
    w = (await call('GET', `/v1/worlds/${worldId}`, rusa.token)).body;
    expect(w.bridge).toMatchObject({ stage: 1, status: 'open', quests: {}, embers: 0 });
    // (The scouts' find may have been an Ember.)
    await db.query('UPDATE worlds SET embers = 0 WHERE id = $1', [worldId]);
    expect((await donate({}, 1)).body.message).toMatch(/has 0 Svarog/);
  });

  it('calls Ritual Night when the bridge is whole, and the run is won when the city outlasts it', async () => {
    const rusa = await guest('Rusa');
    const created = await call('POST', '/v1/worlds', rusa.token, { name: 'Ritual', maxPlayers: 1, speed: 10 });
    const worldId: number = created.body.id;
    const started = await call('POST', `/v1/worlds/${worldId}/start`, rusa.token);
    const stages = scheduler.data.bridge.stages;
    const last = stages[stages.length - 1]!;
    // The last stage paid for, only its ritual torc missing.
    await db.query(
      `UPDATE bridges SET state = state || jsonb_build_object('stage', $2::int, 'donated', $3::jsonb, 'embers', $4::int) WHERE world_id = $1`,
      [worldId, stages.length - 1, JSON.stringify(last.cost), last.embers],
    );
    await db.query('UPDATE worlds SET embers = $2 WHERE id = $1', [worldId, scheduler.data.bridge.ritualEmbers]);
    let w = (await call('POST', `/v1/worlds/${worldId}/bridge/ritual`, rusa.token)).body;
    expect(w.bridge.status).toBe('raising');
    const scheduled = started.body.waves.filter((x: { status: string }) => x.status === 'scheduled').length;
    expect(scheduled).toBeGreaterThan(0);

    // Raised: every active front sends a horde at once; the waves to come are called off.
    now = new Date(w.bridge.raisedAt);
    await tick(db, now, scheduler);
    w = (await call('GET', `/v1/worlds/${worldId}`, rusa.token)).body;
    expect(w.bridge.status).toBe('complete');
    const ritualAt = new Date(w.ritualAt).getTime();
    expect(ritualAt).toBeGreaterThanOrEqual(now.getTime() + (scheduler.data.bridge.ritualNight.delayHours * 3_600_000) / 10);
    const ritual = w.waves.filter((x: { ritual: boolean }) => x.ritual);
    expect(ritual.map((x: { front: string }) => x.front).sort()).toEqual([...w.map.activeFronts].sort());
    expect(w.waves.every((x: { ritual: boolean }) => x.ritual)).toBe(true);
    expect(ritual.every((x: { spawnAt: string }) => new Date(x.spawnAt).getTime() === ritualAt)).toBe(true);
    expect(w.run).toBeNull();

    // They set out; no new wave is announced behind them.
    now = new Date(ritualAt);
    await tick(db, now, scheduler);
    w = (await call('GET', `/v1/worlds/${worldId}`, rusa.token)).body;
    expect(w.status).toBe('running');
    expect(w.waves.every((x: { ritual: boolean; status: string }) => x.ritual && x.status !== 'scheduled')).toBe(true);

    // The last horde is beaten and the city stands: the run is won.
    await db.query("UPDATE waves SET status = 'defeated' WHERE world_id = $1 AND ritual", [worldId]);
    now = new Date(ritualAt + (2 * scheduler.data.bridge.ritualNight.checkHours * 3_600_000) / 10);
    await tick(db, now, scheduler);
    w = (await call('GET', `/v1/worlds/${worldId}`, rusa.token)).body;
    expect(w.status).toBe('won');
    expect(w.endedAt).not.toBeNull();
    expect(w.run).toMatchObject({ outcome: 'won', wavesBeaten: ritual.length, villagesFounded: 1, villagesLost: 0 });
    expect(w.run.members).toEqual([{ accountId: rusa.accountId, displayName: 'Rusa', villages: 1, villagesLost: 0 }]);
    // Telemetry kept the run's start and end, without names.
    const { rows: telemetry } = await db.query<{ kind: string; data: Record<string, unknown> }>(
      "SELECT kind, data FROM telemetry WHERE world_id = $1 AND kind IN ('run_start', 'run_end') ORDER BY id",
      [worldId],
    );
    expect(telemetry.map((t) => t.kind)).toEqual(['run_start', 'run_end']);
    expect(telemetry[1]!.data).toMatchObject({ outcome: 'won', players: 1, wavesBeaten: ritual.length });
    expect(JSON.stringify(telemetry)).not.toContain('Rusa');

    // A finished run stays readable, but nothing more can be done in it.
    const home = started.body.villages[0];
    const refused = await call('POST', `/v1/villages/${home.id}/build`, rusa.token, { plot: 'c2', building: 'barracks' });
    expect(refused.body.message).toMatch(/run is over/);
    expect((await call('GET', `/v1/worlds/${worldId}/notifications`, rusa.token)).status).toBe(200);
  });

  it('lets members pick a clan, whose perks every village carries', async () => {
    const host = await guest('Ljuba');
    const friend = await guest('Goran');
    const created = await call('POST', '/v1/worlds', host.token, { name: 'Clans', maxPlayers: 2 });
    const worldId: number = created.body.id;
    await call('POST', '/v1/worlds/join', friend.token, { inviteCode: created.body.inviteCode });
    expect((await call('PUT', `/v1/worlds/${worldId}/clan`, host.token, { clan: 'lion' })).body.message).toMatch(/Unknown clan/);
    await call('PUT', `/v1/worlds/${worldId}/clan`, host.token, { clan: 'sokol' });
    const lobby = (await call('PUT', `/v1/worlds/${worldId}/clan`, host.token, { clan: 'volk' })).body;
    expect(lobby.members.find((m: { accountId: number }) => m.accountId === host.accountId).clan).toBe('volk');

    const started = (await call('POST', `/v1/worlds/${worldId}/start`, host.token)).body;
    const village = (id: number) => started.villages.find((v: { ownerAccountId: number }) => v.ownerAccountId === id);
    expect(village(host.accountId).bonuses).toMatchObject({ 'clan.volk': 1, 'production.stone': 0.15 });
    expect(village(friend.accountId).bonuses['clan.volk']).toBeUndefined();
    // Once the run is under way, the clan is set; a member without one may still pick.
    expect((await call('PUT', `/v1/worlds/${worldId}/clan`, host.token, { clan: 'rys' })).body.message).toMatch(/chosen for this run/);
    const picked = (await call('PUT', `/v1/worlds/${worldId}/clan`, friend.token, { clan: 'rys' })).body;
    const theirs = picked.villages.find((v: { ownerAccountId: number }) => v.ownerAccountId === friend.accountId);
    expect(theirs.bonuses).toMatchObject({ 'clan.rys': 1, 'production.wood': 0.15 });
    const refused = await call('POST', `/v1/villages/${theirs.id}/build`, friend.token, { plot: 'c2', building: 'longhouse_hall' });
    expect(refused.body.message).toMatch(/Only Rod Volka/);
  });

  it('lets a player hand their villages to a teammate for a while, logging what the teammate does', async () => {
    const mila = await guest('Mila');
    const goran = await guest('Goran');
    const created = await call('POST', '/v1/worlds', mila.token, { name: 'Away', maxPlayers: 2 });
    const worldId: number = created.body.id;
    await call('POST', '/v1/worlds/join', goran.token, { inviteCode: created.body.inviteCode });
    const started = (await call('POST', `/v1/worlds/${worldId}/start`, mila.token)).body;
    const milas = started.villages.find((v: { ownerAccountId: number }) => v.ownerAccountId === mila.accountId);
    const build = () => call('POST', `/v1/villages/${milas.id}/build`, goran.token, { plot: 'c2', building: 'barracks' });
    expect((await build()).status).toBe(403);

    expect((await call('PUT', `/v1/worlds/${worldId}/delegation`, mila.token, { to: goran.accountId, days: 9 })).body.message).toMatch(/1 to 7 days/);
    expect((await call('PUT', `/v1/worlds/${worldId}/delegation`, mila.token, { to: mila.accountId, days: 2 })).body.message).toMatch(/not yourself/);
    let w = (await call('PUT', `/v1/worlds/${worldId}/delegation`, mila.token, { to: goran.accountId, days: 2 })).body;
    expect(w.delegations).toEqual([{ ownerAccountId: mila.accountId, delegateAccountId: goran.accountId, since: now.toISOString(), until: new Date(now.getTime() + 2 * 86_400_000).toISOString() }]);
    // No chains: Goran can't hand his villages to Mila while he looks after hers.
    expect((await call('PUT', `/v1/worlds/${worldId}/delegation`, goran.token, { to: mila.accountId, days: 1 })).body.message).toMatch(/handed over their own/);

    expect((await build()).status).toBe(200);
    w = (await call('GET', `/v1/worlds/${worldId}`, mila.token)).body;
    expect(w.delegationLog).toEqual([
      { ownerAccountId: mila.accountId, delegateAccountId: goran.accountId, villageId: milas.id, action: 'queued a build', at: now.toISOString() },
    ]);
    // Goran hands them back early; then he can't command them any more.
    w = (await call('DELETE', `/v1/worlds/${worldId}/delegation`, goran.token, { owner: mila.accountId })).body;
    expect(w.delegations).toEqual([]);
    expect((await call('POST', `/v1/villages/${milas.id}/train`, goran.token, { unit: 'spearman', count: 1 })).status).toBe(403);

    // A hand-over runs out by itself.
    await call('PUT', `/v1/worlds/${worldId}/delegation`, mila.token, { to: goran.accountId, days: 1 });
    now = new Date(now.getTime() + 86_400_000 + 1000);
    expect((await call('GET', `/v1/worlds/${worldId}`, mila.token)).body.delegations).toEqual([]);
    expect((await build()).status).toBe(403);
  });

  it('rewards the first time a player does each getting-started step', async () => {
    const vesna = await guest('Vesna');
    const created = await call('POST', '/v1/worlds', vesna.token, { name: 'First days', maxPlayers: 1 });
    const worldId: number = created.body.id;
    const started = (await call('POST', `/v1/worlds/${worldId}/start`, vesna.token)).body;
    const home = started.villages[0];
    const before = home.resources.amounts;
    const reward = scheduler.data.onboarding.steps.find((s) => s.id === 'build')!.reward;
    const built = (await call('POST', `/v1/villages/${home.id}/build`, vesna.token, { plot: 'c2', building: 'barracks' })).body;
    const cost = scheduler.data.buildings.buildings.barracks!.cost;
    for (const kind of ['wood', 'stone', 'grain', 'iron'] as const) {
      expect(Math.round(built.village.resources.amounts[kind])).toBe(Math.round(before[kind] - cost[kind] + reward[kind]));
    }
    let w = (await call('GET', `/v1/worlds/${worldId}`, vesna.token)).body;
    expect(w.members[0].onboarding).toEqual({ build: now.toISOString() });
    // Only once.
    const again = (await call('POST', `/v1/villages/${home.id}/build`, vesna.token, { plot: 'f1' })).body;
    expect(again.village.resources.amounts.wood).toBeLessThan(built.village.resources.amounts.wood);
    w = (await call('GET', `/v1/worlds/${worldId}`, vesna.token)).body;
    expect(Object.keys(w.members[0].onboarding)).toEqual(['build']);
  });

  it('reveals a forgotten ruin when the bridge wants a relic and every site was searched', async () => {
    const rusa = await guest('Rusa');
    const created = await call('POST', '/v1/worlds', rusa.token, { name: 'Ruins', maxPlayers: 1, speed: 10 });
    const worldId: number = created.body.id;
    const started = (await call('POST', `/v1/worlds/${worldId}/start`, rusa.token)).body;
    const stages = scheduler.data.bridge.stages;
    const before = stages.findIndex((st, i) => i > 0 && stages[i + 1]?.quests.some((q) => q.kind === 'site'));
    const stage = stages[before]!;
    // Everything but one wood in place for the stage before the one that wants a relic.
    const donated = { ...stage.cost, wood: stage.cost.wood - 1 };
    const quests = Object.fromEntries(stage.quests.map((q) => [q.kind, now.toISOString()]));
    await db.query(
      `UPDATE bridges SET state = state || jsonb_build_object('stage', $2::int, 'donated', $3::jsonb, 'embers', $4::int, 'quests', $5::jsonb) WHERE world_id = $1`,
      [worldId, before, JSON.stringify(donated), stage.embers, JSON.stringify(quests)],
    );
    await db.query(`UPDATE vaults SET amounts = '{"wood": 1, "stone": 0, "grain": 0, "iron": 0}' WHERE world_id = $1`, [worldId]);
    await db.query(`UPDATE sites SET status = 'explored' WHERE world_id = $1`, [worldId]);
    const raising = (await call('POST', `/v1/worlds/${worldId}/bridge/donate`, rusa.token, { resources: { wood: 1, stone: 0, grain: 0, iron: 0 }, embers: 0 })).body;
    expect(raising.bridge.status).toBe('raising');
    now = new Date(raising.bridge.raisedAt);
    await tick(db, now, scheduler);
    const w = (await call('GET', `/v1/worlds/${worldId}`, rusa.token)).body;
    expect(w.bridge.stage).toBe(before + 1);
    expect(w.sites).toHaveLength(started.sites.length + 1);
    expect(w.sites.filter((x: { status: string }) => x.status === 'unexplored')).toHaveLength(1);
  });

  it('keeps armies to bridges over rivers, and lets players build more', async () => {
    const mira = await guest('Mira');
    const created = await call('POST', '/v1/worlds', mira.token, { name: 'Rivers', maxPlayers: 1, speed: 10 });
    const worldId: number = created.body.id;
    const started = (await call('POST', `/v1/worlds/${worldId}/start`, mira.token)).body;
    expect(Array.isArray(started.map.rivers)).toBe(true);
    const home = started.villages[0];
    const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
    const passable = (q: number, r: number) => ['plains', 'forest', 'hills', 'steppe'].includes(terrain.get(`${q},${r}`) ?? '');
    // A river right beside the village, between home and a passable neighbour.
    const dir = [[1, 0], [1, -1], [0, -1], [-1, 0], [-1, 1], [0, 1]].find(([dq, dr]) => passable(home.q + dq!, home.r + dr!))!;
    const across = { q: home.q + dir[0]!, r: home.r + dir[1]! };
    await db.query('DELETE FROM river_edges WHERE world_id = $1', [worldId]);
    const [a, b] = `${home.q},${home.r}` < `${across.q},${across.r}` ? [home, across] : [across, home];
    await db.query("INSERT INTO river_edges (world_id, aq, ar, bq, br, crossing) VALUES ($1, $2, $3, $4, $5, 'none')", [worldId, a.q, a.r, b.q, b.r]);
    await db.query(`UPDATE villages SET garrison = '{"spearman": 20}', amounts = '{"wood": 5000, "stone": 5000, "grain": 5000, "iron": 5000}' WHERE id = $1`, [home.id]);

    const hold = () => call('POST', `/v1/villages/${home.id}/armies`, mira.token, { target: across, units: { spearman: 5 }, orders: 'hold' });
    const around = (await hold()).body.army;
    expect(around.path.length).toBeGreaterThan(2);

    const crossing = (body: object) => call('POST', `/v1/villages/${home.id}/crossings`, mira.token, body);
    expect((await crossing({ a: home, b: { q: home.q + 9, r: home.r } })).body.message).toMatch(/within|No river/);
    // An old map's river along a lake: no bridge leads onto the water.
    await db.query("UPDATE hexes SET terrain = 'lake' WHERE world_id = $1 AND q = $2 AND r = $3", [worldId, across.q, across.r]);
    expect((await crossing({ a: home, b: across })).body.message).toMatch(/both banks/);
    await db.query('UPDATE hexes SET terrain = $4 WHERE world_id = $1 AND q = $2 AND r = $3', [worldId, across.q, across.r, terrain.get(`${across.q},${across.r}`)]);
    let w = (await crossing({ a: home, b: across })).body;
    expect(w.map.rivers).toEqual([[a.q, a.r, b.q, b.r, 'building', 1]]);
    expect((await crossing({ a: across, b: home })).body.message).toMatch(/being built/);
    now = new Date(now.getTime() + (scheduler.data.field.bridge.buildSeconds * 1000) / 10);
    await tick(db, now, scheduler);
    w = (await call('GET', `/v1/worlds/${worldId}`, mira.token)).body;
    expect(w.map.rivers).toEqual([[a.q, a.r, b.q, b.r, 'standing', 1]]);
    // Over the bridge: straight across.
    expect((await hold()).body.army.path).toHaveLength(2);
  });

  it('builds roads that speed up the march', async () => {
    const mira = await guest('Mira');
    const created = await call('POST', '/v1/worlds', mira.token, { name: 'Roads', maxPlayers: 1, speed: 10 });
    const worldId: number = created.body.id;
    const started = (await call('POST', `/v1/worlds/${worldId}/start`, mira.token)).body;
    const home = started.villages[0];
    const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
    const passable = (q: number, r: number) => ['plains', 'forest', 'hills', 'steppe'].includes(terrain.get(`${q},${r}`) ?? '');
    const dir = [[1, 0], [1, -1], [0, -1], [-1, 0], [-1, 1], [0, 1]].find(([dq, dr]) => passable(home.q + dq!, home.r + dr!))!;
    const next = { q: home.q + dir[0]!, r: home.r + dir[1]! };
    await db.query('DELETE FROM river_edges WHERE world_id = $1', [worldId]);
    await db.query(`UPDATE villages SET garrison = '{"spearman": 20}', amounts = '{"wood": 5000, "stone": 5000, "grain": 5000, "iron": 5000}' WHERE id = $1`, [home.id]);
    const march = async () => {
      const army = (await call('POST', `/v1/villages/${home.id}/armies`, mira.token, { target: next, units: { spearman: 1 }, orders: 'hold' })).body.army;
      return new Date(army.arrivesAt).getTime() - now.getTime();
    };
    const offRoad = await march();

    const road = (body: object) => call('POST', `/v1/villages/${home.id}/roads`, mira.token, body);
    expect((await road({ a: home, b: { q: home.q + 2, r: home.r } })).body.message).toMatch(/neighbouring/);
    expect((await road({ a: { q: home.q + 8, r: home.r }, b: { q: home.q + 9, r: home.r } })).body.message).toMatch(/within/);
    let w = (await road({ a: home, b: next })).body;
    expect(w.map.roads).toHaveLength(1);
    expect(w.map.roads[0][4]).toBe('building');
    expect((await road({ a: next, b: home })).body.message).toMatch(/already/);
    now = new Date(now.getTime() + (scheduler.data.field.road.buildSeconds * 1000) / 10);
    await tick(db, now, scheduler);
    w = (await call('GET', `/v1/worlds/${worldId}`, mira.token)).body;
    expect(w.map.roads[0][4]).toBe('standing');
    expect(await march()).toBe(Math.round(offRoad * scheduler.data.field.road.factor));
  });

  it('fights at the walls: siege works, battering, towers and a breach', async () => {
    const zora = await guest('Zora');
    const created = await call('POST', '/v1/worlds', zora.token, { name: 'Walls', maxPlayers: 1, speed: 10 });
    const worldId: number = created.body.id;
    const started = await call('POST', `/v1/worlds/${worldId}/start`, zora.token);
    const village = started.body.villages[0];
    expect(village.plots.w).toEqual({ building: 'wall', level: 0 });
    // Raise the walls at once (level 6), with an archer tower in the first slot.
    const { rows } = await db.query<{ plots: Record<string, unknown> }>('SELECT plots FROM villages WHERE id = $1', [village.id]);
    const plots = { ...rows[0]!.plots, w: { building: 'wall', level: 6 }, t0: { building: 'archer_tower', level: 3 } };
    await db.query(`UPDATE villages SET plots = $2, garrison = '{"spearman": 25}' WHERE id = $1`, [village.id, JSON.stringify(plots)]);
    now = new Date(started.body.waves[0].spawnAt);
    await tick(db, now, scheduler);
    let world = (await call('GET', `/v1/worlds/${worldId}`, zora.token)).body;
    now = new Date(world.waves[0].arrivesAt);
    await tick(db, now, scheduler);
    world = (await call('GET', `/v1/worlds/${worldId}`, zora.token)).body;
    const battle = world.battles[0];
    // Stone walls: toughness 1.35.
    const integrity = Math.round(120 * 6 * 1.35);
    expect(battle.setup.wall).toEqual({ level: 6, integrity, max: integrity });
    // A front that builds engines sets them up first; the assault waits.
    const front = scheduler.data.enemies.fronts[battle.front as 'north']!;
    if (battle.setup.siege) {
      expect(battle.setup.siege.engine).toBe(front.engine);
      expect(battle.attackerInitial[front.engine!]).toBeGreaterThanOrEqual(battle.setup.siege.count);
      now = new Date(battle.setup.siege.readyAt);
    }
    for (let round = 0; round < 12; round++) {
      now = new Date(now.getTime() + (15 * 60_000) / 10);
      await tick(db, now, scheduler);
    }
    world = (await call('GET', `/v1/worlds/${worldId}`, zora.token)).body;
    const fought = world.battles[0];
    expect(fought.status).not.toBe('ongoing');
    const lefts = fought.rounds.map((r: { wallLeft?: number }) => r.wallLeft).filter((n: number | undefined) => n !== undefined);
    expect(lefts.length).toBeGreaterThan(0);
    expect(lefts).toEqual([...lefts].sort((a: number, b: number) => b - a));
    expect(lefts[0]).toBeLessThan(integrity);
    // A breach knocks the walls down a level.
    const after = world.villages.find((v: { id: number }) => v.id === village.id);
    const breached = lefts.at(-1) === 0;
    expect(after.plots.w.level).toBe(breached ? 5 : 6);
    const { rows: results } = await db.query<{ data: { where: string; walls: number } }>("SELECT data FROM telemetry WHERE world_id = $1 AND kind = 'wave_result'", [worldId]);
    expect(results[0]!.data).toMatchObject({ where: 'village', walls: 6 });
    expect(fought.rounds.some((r: { breach?: boolean }) => r.breach)).toBe(breached);
  });

  it('exports, reports and deletes an account that hosts a world and owns a village', async () => {
    const ana = await guest('Ana');
    const other = await guest('Other');
    const renamed = await call('PATCH', '/v1/me', ana.token, { language: 'sr_Latn' });
    expect(renamed.body.account.language).toBe('sr_Latn');
    const created = await call('POST', '/v1/worlds', ana.token, { name: 'Leaving', maxPlayers: 1 });
    const worldId: number = created.body.id;
    const started = await call('POST', `/v1/worlds/${worldId}/start`, ana.token);
    const villageId: number = started.body.villages[0].id;
    // A report names only a world its sender plays in.
    const mine = await call('POST', '/v1/reports', ana.token, { message: 'The map froze', worldId, state: { view: 'map' } });
    const theirs = await call('POST', '/v1/reports', other.token, { message: 'Not my world', worldId });
    const gone = await call('POST', '/v1/reports', ana.token, { message: 'Old world', worldId: 999999 });
    expect([mine.status, theirs.status, gone.status]).toEqual([200, 200, 200]);
    const { rows: reports } = await db.query<{ id: string; world_id: string | null }>('SELECT id, world_id FROM reports WHERE id = ANY($1) ORDER BY id', [
      [mine.body.id, theirs.body.id, gone.body.id],
    ]);
    expect(reports.map((r) => r.world_id === null ? null : Number(r.world_id))).toEqual([worldId, null, null]);
    const exported = await call('GET', '/v1/me/export', ana.token);
    expect(exported.body.settings.language).toBe('sr_Latn');
    expect(exported.body.worlds.map((w: { world_id: number }) => Number(w.world_id))).toEqual([worldId]);
    expect(exported.body.villages.map((v: { id: number }) => Number(v.id))).toEqual([villageId]);
    expect(exported.body.reports).toHaveLength(2);
    // Deleting leaves the world and the village standing, without an owner.
    expect((await call('DELETE', '/v1/me', ana.token)).status).toBe(200);
    expect((await call('GET', '/v1/me', ana.token)).status).toBe(401);
    const { rows } = await db.query<{ owner: string | null; host: string | null }>(
      'SELECT v.owner_account_id AS owner, w.host_account_id AS host FROM villages v JOIN worlds w ON w.id = v.world_id WHERE v.id = $1',
      [villageId],
    );
    expect(rows[0]).toEqual({ owner: null, host: null });
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
