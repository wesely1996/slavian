import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { createGuestAccount } from '../src/db/accounts.js';
import { inTransaction, type Db } from '../src/db/pool.js';
import { upgradeLegacyVillages, upgradeTownNames } from '../src/db/upgrades.js';
import { insertVillage, loadVillage } from '../src/db/villages.js';
import { createWorld } from '../src/db/worlds.js';
import { scheduleEvent } from '../src/scheduler/events.js';
import { handlers } from '../src/scheduler/handlers.js';
import { tick } from '../src/scheduler/worker.js';
import { newVillage } from '../src/sim/village.js';
import { createTestDb, TEST_DATABASE_URL } from './db.js';

const data = loadGameData();
const T0 = new Date('2026-06-01T00:00:00Z');

describe.skipIf(!TEST_DATABASE_URL)('legacy village upgrade (postgres)', () => {
  let db: Db;
  let cleanup: () => Promise<void>;
  beforeAll(async () => {
    ({ db, cleanup } = await createTestDb());
  });
  afterAll(async () => {
    await cleanup?.();
  });

  it('lays out an old village on plots and finishes its pending build', async () => {
    const { worldId, villageId } = await inTransaction(db, async (client) => {
      const { account } = await createGuestAccount(client, 'Old timer');
      const world = await createWorld(client, { name: 'old', seed: 1, speed: 1 });
      const village = await insertVillage(client, {
        worldId: world.id,
        ownerAccountId: account.id,
        name: 'v',
        q: 2,
        r: 0,
        state: newVillage(data, T0, 1),
      });
      return { worldId: world.id, villageId: village.id };
    });
    // Make it look like it was saved before plots existed: levels only, a
    // queued barracks without a plot, and an event without a plot.
    const completesAt = new Date(T0.getTime() + 60_000);
    await db.query(
      `UPDATE villages SET plots = NULL, levels = '{"woodcutter": 2, "storehouse": 1}',
       queue = $2 WHERE id = $1`,
      [villageId, JSON.stringify([{ building: 'barracks', targetLevel: 1, startsAt: T0, completesAt }])],
    );
    await inTransaction(db, (client) =>
      scheduleEvent(client, worldId, completesAt, 'build_complete', { villageId, building: 'barracks', targetLevel: 1 }),
    );

    expect(await upgradeLegacyVillages(db, data)).toBe(1);
    expect(await upgradeLegacyVillages(db, data)).toBe(0);
    let village = await inTransaction(db, (client) => loadVillage(client, villageId));
    expect(village.state.plots.f0).toEqual({ building: 'woodcutter', level: 2 });
    expect(village.state.plots.c1).toEqual({ building: 'storehouse', level: 1 });
    expect(village.state.queue[0]!.plot).toBe('c2');

    await tick(db, completesAt, { data, handlers });
    village = await inTransaction(db, (client) => loadVillage(client, villageId));
    expect(village.state.plots.c2).toEqual({ building: 'barracks', level: 1 });
    expect(village.state.levels).toMatchObject({ woodcutter: 2, storehouse: 1, barracks: 1, elder_hall: 1 });
  });

  it('names towns that still carry the old default names', async () => {
    const ids = await inTransaction(db, async (client) => {
      const { account } = await createGuestAccount(client, 'Mila');
      const world = await createWorld(client, { name: 'named', seed: 5, speed: 1 });
      const ids: number[] = [];
      for (const [i, name] of ["Mila's village", "Mila's village 2", 'Kitezh'].entries()) {
        const village = await insertVillage(client, { worldId: world.id, ownerAccountId: account.id, name, q: 2 + i, r: 0, state: newVillage(data, T0, 1) });
        ids.push(village.id);
      }
      return ids;
    });
    expect(await upgradeTownNames(db, data)).toBe(2);
    expect(await upgradeTownNames(db, data)).toBe(0);
    const names: string[] = [];
    for (const id of ids) names.push((await inTransaction(db, (client) => loadVillage(client, id))).name);
    expect(names[2]).toBe('Kitezh');
    expect(new Set(names).size).toBe(3);
    for (const name of names) expect(name).not.toMatch(/'s village/);
  });
});
