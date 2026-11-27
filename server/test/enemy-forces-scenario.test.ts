// The enemy's forces in a solo session (enemy-lands.json forces): an army
// without scouts marches deep into a front's lands and holds two hexes from
// its seat. The seat's scouts spot it at a watch; a sally marches out,
// catches it and fights it, and what is left of the sally goes home. Two
// game days on, each front has two settlements and its patrols set out
// between them.
import { hex, hexDistance, spiral } from '../src/sim/hex.js';
import { MINUTE, scenario, scheduler } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Forces', displayName: 'You', speed: 50, difficulty: 'baron' };
const HOUR = (60 * MINUTE) / START.speed;

scenario('enemy-forces-scenario.json', START, async ({ started, play }) => {
  const world = '/v1/worlds/-1';
  for (const front of started.map.activeFronts as string[]) await play({ set: { enemySight: { front, bands: 4 } } });
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'barracks' } });
  await play({ set: { amounts: { wood: 5000, stone: 5000, grain: 5000, iron: 5000 } } });
  await play({ advance: 20 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 12 } });
  await play({ advance: 60 * MINUTE });
  const view = (await play({ method: 'GET', path: world })).body;
  const seat = (view.map.settlements as { kind: string; q: number; r: number }[]).find((s) => s.kind === 'seat')!;
  // A hex two from the seat an army can reach.
  let army: { id: number } | null = null;
  for (const cell of spiral(hex(seat.q, seat.r), 2).filter((c) => hexDistance(c, hex(seat.q, seat.r)) === 2)) {
    const sent = await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: { q: cell.q, r: cell.r }, units: { spearman: 12 } } });
    if (sent.status === 200) {
      army = sent.body.army;
      break;
    }
  }
  if (!army) throw new Error('No way to the seat');
  for (let i = 0; i < 16; i++) {
    await play({ advance: 2 * HOUR });
    await play({ method: 'GET', path: world });
  }
  const day = scheduler.data.seasons.dayHours * HOUR;
  await play({ advance: 2 * day });
  await play({ method: 'GET', path: world });
  for (let i = 0; i < 3; i++) {
    await play({ advance: scheduler.data.enemyLands.forces.patrols.everyHours * HOUR });
    await play({ method: 'GET', path: world });
  }
}, 120_000);
