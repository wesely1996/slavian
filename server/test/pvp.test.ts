// Player against player (armies.json pvp): two players in a PvP world. A
// village is protected after it is founded; then an army attacks it,
// plunders it, razes it, or is beaten off. No armies help rivals,
// and outside a PvP world nobody attacks anybody.
import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/api/app.js';
import { loadGameData } from '../src/data/index.js';
import type { Db } from '../src/db/pool.js';
import { handlers } from '../src/scheduler/handlers.js';
import { tick } from '../src/scheduler/worker.js';
import { createTestDb, TEST_DATABASE_URL } from './db.js';

const scheduler = { data: loadGameData(), handlers };
scheduler.data.events.kinds.ritual.weight = 0;

describe.skipIf(!TEST_DATABASE_URL)('pvp (postgres)', () => {
  let db: Db;
  let cleanup: () => Promise<void>;
  let app: FastifyInstance;
  let now = new Date('2026-05-01T10:00:00Z');
  const clock = () => now;

  beforeAll(async () => {
    ({ db, cleanup } = await createTestDb());
    app = await buildApp({ db, scheduler, clock });
  });
  afterAll(async () => {
    await app?.close();
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
  async function guest(displayName: string): Promise<string> {
    return (await call('POST', '/v1/auth/guest', undefined, { displayName })).body.token;
  }
  // Two players in a fresh world; their first villages.
  async function twoPlayers(pvp: boolean) {
    const vesna = await guest('Vesna');
    const bogdan = await guest('Bogdan');
    const created = (await call('POST', '/v1/worlds', vesna, { name: 'Rivals', maxPlayers: 2, speed: 10, pvp })).body;
    expect(created.pvp).toBe(pvp);
    await call('POST', '/v1/worlds/join', bogdan, { inviteCode: created.inviteCode });
    const started = (await call('POST', `/v1/worlds/${created.id}/start`, vesna)).body;
    const [first, second] = started.villages as { id: number; ownerAccountId: number }[];
    const mine = started.members.find((m: { displayName: string }) => m.displayName === 'Vesna').accountId;
    const vesnaVillage = first!.ownerAccountId === mine ? first! : second!;
    const bogdanVillage = first!.ownerAccountId === mine ? second! : first!;
    // No camps or hordes in the way.
    await db.query('DELETE FROM camps WHERE world_id = $1', [created.id]);
    await db.query("UPDATE waves SET status = 'dispersed' WHERE world_id = $1", [created.id]);
    return { worldId: created.id as number, vesna, bogdan, vesnaVillage: vesnaVillage.id, bogdanVillage: bogdanVillage.id };
  }
  const setGarrison = (id: number, garrison: Record<string, number>) =>
    db.query('UPDATE villages SET garrison = $2 WHERE id = $1', [id, JSON.stringify(garrison)]);
  const setStores = (id: number, n: number) =>
    db.query('UPDATE villages SET amounts = $2, settled_at = $3 WHERE id = $1', [id, JSON.stringify({ wood: n, stone: n, grain: n, iron: n }), now]);
  const unprotect = (id: number) => db.query("UPDATE villages SET founded_at = $2 WHERE id = $1", [id, new Date(now.getTime() - 30 * 86_400_000)]);
  const attack = (token: string, from: number, to: number, units: Record<string, number>, orders = 'attack') =>
    call('POST', `/v1/villages/${from}/armies`, token, { orders, targetVillageId: to, units });
  async function arrive(token: string, army: { arrivesAt: string }) {
    now = new Date(army.arrivesAt);
    await tick(db, now, scheduler);
  }
  async function lastBattle(token: string, worldId: number) {
    const world = (await call('GET', `/v1/worlds/${worldId}`, token)).body;
    return { world, battle: (world.battles as { status: string; villageId: number }[])[0]! };
  }

  it('protects a new village, then lets a rival plunder it', async () => {
    const w = await twoPlayers(true);
    await setGarrison(w.vesnaVillage, { axe_levy: 40 });
    await setGarrison(w.bogdanVillage, { axe_levy: 2 });
    await setStores(w.bogdanVillage, 1000);
    const early = await attack(w.vesna, w.vesnaVillage, w.bogdanVillage, { axe_levy: 30 });
    expect(early.body.message).toMatch(/under protection/);
    await unprotect(w.bogdanVillage);
    // No help for a rival.
    expect((await call('POST', `/v1/villages/${w.vesnaVillage}/armies`, w.vesna, { orders: 'support', targetVillageId: w.bogdanVillage, units: { axe_levy: 1 } })).body.message).toMatch(/own villages/);
    const sent = await attack(w.vesna, w.vesnaVillage, w.bogdanVillage, { axe_levy: 30 });
    expect(sent.body).toMatchObject({ army: {} });
    await arrive(w.vesna, sent.body.army);
    const { world, battle } = await lastBattle(w.vesna, w.worldId);
    expect(battle.status).toBe('raided');
    const army = (world.armies as { id: number; status: string; loot: Record<string, number> | null }[]).find((a) => a.id === sent.body.army.id)!;
    expect(army.status).toBe('returning');
    expect(Object.values(army.loot ?? {}).reduce((a, b) => a + b, 0)).toBeGreaterThan(0);
    const inbox = (await call('GET', `/v1/worlds/${w.worldId}/notifications`, w.bogdan)).body.notifications as { title: string }[];
    expect(inbox.some((n) => /plundered by Vesna/.test(n.title))).toBe(true);
  });

  it('razes a village when told to, and is beaten off by a strong garrison', async () => {
    const w = await twoPlayers(true);
    await unprotect(w.bogdanVillage);
    await unprotect(w.vesnaVillage);
    await setGarrison(w.vesnaVillage, { axe_levy: 40 });
    await setGarrison(w.bogdanVillage, { spearman: 40 });
    // Beaten off.
    const beaten = await attack(w.vesna, w.vesnaVillage, w.bogdanVillage, { axe_levy: 5 });
    await arrive(w.vesna, beaten.body.army);
    expect((await lastBattle(w.vesna, w.worldId)).battle.status).toBe('defended');
    // Razed.
    await setGarrison(w.bogdanVillage, {});
    const raze = await attack(w.vesna, w.vesnaVillage, w.bogdanVillage, { axe_levy: 30 }, 'raze');
    await arrive(w.vesna, raze.body.army);
    const { world, battle } = await lastBattle(w.vesna, w.worldId);
    expect(battle.status).toBe('raided');
    const razed = (world.villages as { id: number; ruin: unknown }[]).find((v) => v.id === w.bogdanVillage)!;
    expect(razed.ruin).toBeTruthy();
  });

  it("doesn't let players attack each other outside a PvP world", async () => {
    const w = await twoPlayers(false);
    await setGarrison(w.vesnaVillage, { axe_levy: 10 });
    expect((await attack(w.vesna, w.vesnaVillage, w.bogdanVillage, { axe_levy: 5 })).body.message).toMatch(/don't attack each other/);
  });
});
