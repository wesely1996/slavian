import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { queueBuildCommand } from '../src/commands/queue-build.js';
import { loadGameData } from '../src/data/index.js';
import { inTransaction, type Db } from '../src/db/pool.js';
import { insertVillage, loadVillage } from '../src/db/villages.js';
import { createWorld } from '../src/db/worlds.js';
import { scheduleEvent, type HandlerRegistry, type SchedulerDeps } from '../src/scheduler/events.js';
import { handlers } from '../src/scheduler/handlers.js';
import { processWorld, tick } from '../src/scheduler/worker.js';
import { lockWorld } from '../src/scheduler/world.js';
import { amountsAt } from '../src/sim/resources.js';
import { newVillage } from '../src/sim/village.js';
import { createTestDb, TEST_DATABASE_URL } from './db.js';

const data = loadGameData();
const deps: SchedulerDeps = { data, handlers };
const T0 = new Date('2026-03-01T08:00:00Z');
const seconds = (n: number) => new Date(T0.getTime() + n * 1000);

describe.skipIf(!TEST_DATABASE_URL)('scheduler (postgres)', () => {
  let db: Db;
  let cleanup: () => Promise<void>;

  beforeAll(async () => {
    ({ db, cleanup } = await createTestDb());
  });
  afterAll(async () => {
    await cleanup?.();
  });

  async function setup(speed = 1) {
    return inTransaction(db, async (client) => {
      const world = await createWorld(client, { name: 'test', seed: 1, speed });
      const village = await insertVillage(client, {
        worldId: world.id,
        name: 'v',
        q: 2,
        r: 0,
        state: newVillage(data, T0, speed),
      });
      return { worldId: world.id, villageId: village.id };
    });
  }

  const village = (id: number) => inTransaction(db, (client) => loadVillage(client, id));

  async function eventStatuses(worldId: number) {
    const { rows } = await db.query<{ type: string; status: string }>(
      'SELECT type, status FROM scheduled_events WHERE world_id = $1 ORDER BY id',
      [worldId],
    );
    return rows;
  }

  it('completes a build when it is due, not before', async () => {
    const { villageId } = await setup();
    const queued = await queueBuildCommand(db, deps, { villageId, building: 'woodcutter', now: T0 });

    await tick(db, new Date(queued.completesAt.getTime() - 1), deps);
    expect((await village(villageId)).state.levels.woodcutter).toBeUndefined();

    await tick(db, queued.completesAt, deps);
    const after = await village(villageId);
    expect(after.state.levels.woodcutter).toBe(1);
    expect(after.state.queue).toHaveLength(0);
  });

  it('gives the same result whether the worker is on time or an hour late', async () => {
    const onTime = await setup();
    const late = await setup();
    const queued = await queueBuildCommand(db, deps, { villageId: onTime.villageId, building: 'farm', now: T0 });
    await queueBuildCommand(db, deps, { villageId: late.villageId, building: 'farm', now: T0 });

    await tick(db, queued.completesAt, deps);
    await tick(db, seconds(3600), deps);

    const at = seconds(7200);
    const a = await village(onTime.villageId);
    const b = await village(late.villageId);
    expect(b.state.levels).toEqual(a.state.levels);
    expect(amountsAt(b.state.ledger, at)).toEqual(amountsAt(a.state.ledger, at));
  });

  it('commands catch the world up before acting', async () => {
    const { villageId } = await setup();
    const first = await queueBuildCommand(db, deps, { villageId, building: 'woodcutter', now: T0 });
    // No worker ran, but the first build is already due when the next command arrives.
    const later = new Date(first.completesAt.getTime() + 1000);
    const second = await queueBuildCommand(db, deps, { villageId, building: 'woodcutter', now: later });

    expect(second.targetLevel).toBe(2);
    expect(second.startsAt).toEqual(later);
    const v = await village(villageId);
    expect(v.state.levels.woodcutter).toBe(1);
    expect(v.state.queue).toHaveLength(1);
  });

  it('skips a world that someone else holds, then processes it later', async () => {
    const { worldId, villageId } = await setup();
    const queued = await queueBuildCommand(db, deps, { villageId, building: 'quarry', now: T0 });

    const holder = await db.connect();
    try {
      await holder.query('BEGIN');
      await lockWorld(holder, worldId);
      expect(await processWorld(db, worldId, queued.completesAt, deps)).toBeNull();
      await holder.query('COMMIT');
    } finally {
      holder.release();
    }
    expect(await processWorld(db, worldId, queued.completesAt, deps)).toBe(1);
    expect((await village(villageId)).state.levels.quarry).toBe(1);
  });

  it('processes each event exactly once under concurrent workers', async () => {
    const worlds = await Promise.all([setup(), setup(), setup()]);
    for (const { villageId } of worlds) {
      await queueBuildCommand(db, deps, { villageId, building: 'woodcutter', now: T0 });
      await queueBuildCommand(db, deps, { villageId, building: 'farm', now: T0 });
    }
    const until = seconds(3600);
    await Promise.all(Array.from({ length: 6 }, () => tick(db, until, deps)));
    // Any world skipped because it was busy is caught by a follow-up tick.
    await tick(db, until, deps);

    for (const { worldId, villageId } of worlds) {
      const v = await village(villageId);
      expect(v.state.levels).toEqual({ woodcutter: 1, farm: 1 });
      expect(await eventStatuses(worldId)).toEqual([
        { type: 'build_complete', status: 'done' },
        { type: 'build_complete', status: 'done' },
      ]);
    }
  });

  it('a failing event is marked failed and does not block later ones', async () => {
    const { worldId } = await setup();
    const seen: string[] = [];
    const testDeps: SchedulerDeps = {
      data,
      handlers: {
        async boom() {
          seen.push('boom');
          throw new Error('kaboom');
        },
        async ok() {
          seen.push('ok');
        },
      } satisfies HandlerRegistry,
    };
    await inTransaction(db, async (client) => {
      await scheduleEvent(client, worldId, seconds(1), 'boom', {});
      await scheduleEvent(client, worldId, seconds(2), 'ok', {});
    });
    await tick(db, seconds(10), testDeps);

    expect(seen).toEqual(['boom', 'ok']);
    const { rows } = await db.query<{ type: string; status: string; error: string | null }>(
      'SELECT type, status, error FROM scheduled_events WHERE world_id = $1 ORDER BY id',
      [worldId],
    );
    expect(rows).toEqual([
      { type: 'boom', status: 'failed', error: 'kaboom' },
      { type: 'ok', status: 'done', error: null },
    ]);
  });

  it('runs follow-up events scheduled by a handler in due order within one pass', async () => {
    const { worldId } = await setup();
    const seen: string[] = [];
    const testDeps: SchedulerDeps = {
      data,
      handlers: {
        async first({ client }, event) {
          seen.push('first');
          // Due before "last", so it must run before it.
          await scheduleEvent(client, event.worldId, seconds(3), 'second', {});
        },
        async second() {
          seen.push('second');
        },
        async last() {
          seen.push('last');
        },
      },
    };
    await inTransaction(db, async (client) => {
      await scheduleEvent(client, worldId, seconds(1), 'first', {});
      await scheduleEvent(client, worldId, seconds(5), 'last', {});
    });
    const result = await tick(db, seconds(10), testDeps);

    expect(seen).toEqual(['first', 'second', 'last']);
    expect(result.events).toBe(3);
  });
});
