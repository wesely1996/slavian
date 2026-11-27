// The enemy's settlements on the scheduler (sim/enemySettlements.ts): each
// active front founds the next of its settlements every few game days
// (enemy_found), and every few game hours each that builds does one work
// (enemy_works): a wall, a stretch of road, a bridge, a moat, a tier. Their
// lands get their rivers the first time (ensureEnemyLands).
import type { GameData } from '../data/index.js';
import { edgeWallAt, insertEnemyWall, listEdgeWalls, saveEdgeWall } from '../db/edgeWalls.js';
import { insertEnemySettlement, listEnemySettlements } from '../db/enemySettlements.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { insertRivers, listRiverEdges, setCrossing } from '../db/rivers.js';
import { insertEnemyRoad, listRoadEdges } from '../db/roads.js';
import type { World } from '../db/worlds.js';
import { enemyRivers, nextWork, roadTarget, settlementLevel, settlementSite, type EdgeState, type EnemyWork } from '../sim/enemySettlements.js';
import { edgeKey } from '../sim/land.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';

const MS_PER_HOUR = 3_600_000;

function foundEveryMs(data: GameData, world: World): number {
  return (data.enemyLands.settlements.everyDays * data.seasons.dayHours * MS_PER_HOUR) / world.speed;
}

function worksEveryMs(data: GameData, world: World): number {
  return (data.enemyLands.settlements.worksEveryHours * MS_PER_HOUR) / world.speed;
}

async function pending(client: DbClient, worldId: number, type: string): Promise<boolean> {
  const { rows } = await client.query("SELECT 1 FROM scheduled_events WHERE world_id = $1 AND type = $2 AND status = 'pending'", [worldId, type]);
  return rows.length > 0;
}

// The enemy lands of a running world given their rivers, their first
// settlements and the calendar of what comes next (worlds from before them
// too: from now).
export async function ensureEnemyLands(client: DbClient, data: GameData, world: World, now: Date): Promise<void> {
  if (world.status !== 'running' || !world.startedAt || world.radius === null || !world.activeFronts.length) return;
  if (!(await pending(client, world.id, 'enemy_found'))) {
    await insertRivers(client, world.id, enemyRivers(data, world));
    if (!(await listEnemySettlements(client, world.id)).length) await foundSettlements(client, data, world, now);
    const every = foundEveryMs(data, world);
    const rounds = Math.floor((now.getTime() - world.startedAt.getTime()) / every) + 1;
    await scheduleEvent(client, world.id, new Date(world.startedAt.getTime() + rounds * every), 'enemy_found', {});
  }
  if (!(await pending(client, world.id, 'enemy_works'))) {
    await scheduleEvent(client, world.id, new Date(now.getTime() + worksEveryMs(data, world)), 'enemy_works', {});
  }
}

// Every active front founds its next settlement, if it has one left.
async function foundSettlements(client: DbClient, data: GameData, world: World, at: Date): Promise<void> {
  const all = await listEnemySettlements(client, world.id);
  const taken = all.map((s) => s.cell);
  for (const front of world.activeFronts) {
    const index = all.filter((s) => s.front === front).length;
    const site = settlementSite(data, world, front, index, taken);
    if (!site) continue;
    await insertEnemySettlement(client, world.id, { front, kind: site.kind, band: site.band, cell: site.cell, foundedAt: at });
    taken.push(site.cell);
  }
  await notifyWorld(client, { worldId: world.id, type: 'world' });
}

async function edgeState(client: DbClient, worldId: number): Promise<{ walls: Map<string, { tier: number; gate: boolean }>; roads: Set<string>; rivers: Map<string, boolean> }> {
  return {
    walls: new Map((await listEdgeWalls(client, worldId)).filter((w) => w.status !== 'building').map((w) => [edgeKey(w.a, w.b), { tier: w.tier, gate: w.kind === 'gate' }])),
    roads: new Set((await listRoadEdges(client, worldId)).map((e) => edgeKey(e.a, e.b))),
    rivers: new Map((await listRiverEdges(client, worldId)).map((e) => [edgeKey(e.a, e.b), e.crossing === 'standing'])),
  };
}

async function doWork(client: DbClient, worldId: number, front: string, work: EnemyWork, state: ReturnType<typeof edgeState> extends Promise<infer T> ? T : never): Promise<void> {
  const key = edgeKey(work.a, work.b);
  if (work.kind === 'wall') {
    await insertEnemyWall(client, worldId, work.a, work.b, front);
    state.walls.set(key, { tier: 1, gate: false });
  } else if (work.kind === 'raise') {
    const wall = await edgeWallAt(client, worldId, work.a, work.b);
    if (wall) await saveEdgeWall(client, worldId, { ...wall, tier: work.tier });
    state.walls.set(key, { ...state.walls.get(key)!, tier: work.tier });
  } else if (work.kind === 'road') {
    await insertEnemyRoad(client, worldId, work.a, work.b);
    state.roads.add(key);
    for (const g of work.gates) {
      const wall = await edgeWallAt(client, worldId, g.a, g.b);
      if (wall) await saveEdgeWall(client, worldId, { ...wall, kind: 'gate' });
      state.walls.set(edgeKey(g.a, g.b), { ...state.walls.get(edgeKey(g.a, g.b))!, gate: true });
    }
  } else if (work.kind === 'bridge') {
    await setCrossing(client, worldId, work.a, work.b, 'standing');
    state.rivers.set(key, true);
  } else {
    await insertRivers(client, worldId, [{ a: work.a, b: work.b, bridge: work.bridged, size: 1 }]);
    state.rivers.set(key, work.bridged);
  }
}

export const enemySettlementHandlers: HandlerRegistry = {
  async enemy_found({ client, data, world }, event) {
    if (world.status !== 'running') return;
    await foundSettlements(client, data, world, event.dueAt);
    await scheduleEvent(client, world.id, new Date(event.dueAt.getTime() + foundEveryMs(data, world)), 'enemy_found', {});
  },

  async enemy_works({ client, data, world }, event) {
    if (world.status !== 'running') return;
    const all = await listEnemySettlements(client, world.id);
    const state = await edgeState(client, world.id);
    let built = false;
    const spots = all.map((o) => ({ id: o.id, front: o.front, kind: o.kind, cell: o.cell, level: settlementLevel(data, o.foundedAt, event.dueAt, world.speed) }));
    for (const spot of spots) {
      const target = roadTarget(spot, spots);
      const work = nextWork(data, world, spot, target?.cell ?? null, state as EdgeState);
      if (!work) continue;
      await doWork(client, world.id, spot.front, work, state);
      built = true;
    }
    if (built) await notifyWorld(client, { worldId: world.id, type: 'world' });
    await scheduleEvent(client, world.id, new Date(event.dueAt.getTime() + worksEveryMs(data, world)), 'enemy_works', {});
  },
};
