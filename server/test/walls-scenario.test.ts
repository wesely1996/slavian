// Walls along hex edges in a solo session (field.json edgeWalls): a wall
// beside the village, raised tier by tier (refused while it is raised and
// once it is stone); an army marches round it, and through a gatehouse on
// another edge (no wall goes where the gatehouse stands). One is torn down.
// Then every other edge of the village and of the Holy City is walled: the
// first horde, unable to go round, tears one down on its way in.
import { hex, hexDistance, neighbors } from '../src/sim/hex.js';
import { edgeKey } from '../src/sim/land.js';
import { MINUTE, scenario, scheduler } from './scenario.js';

const START = { seed: 6262, at: '2026-06-01T08:00:00.000Z', name: 'Walls', displayName: 'You', speed: 50, difficulty: 'baron' };

scenario('walls-scenario.json', START, async ({ started, now, play }) => {
  const world = '/v1/worlds/-1';
  const home = started.villages[0] as { q: number; r: number };
  const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const passable = (q: number, r: number) => {
    const t = terrain.get(`${q},${r}`);
    return t !== undefined && t !== 'holy_city' && scheduler.data.terrain.terrain[t as keyof typeof scheduler.data.terrain.terrain].moveCost !== null;
  };
  const rivers = new Set((started.map.rivers as [number, number, number, number][]).map(([aq, ar, bq, br]) => edgeKey(hex(aq, ar), hex(bq, br))));
  const at = hex(home.q, home.r);
  const edges = neighbors(at).filter((n) => passable(n.q, n.r) && !rivers.has(edgeKey(at, n)));
  if (edges.length < 3) throw new Error('No room for walls');
  const [first, second] = edges;
  const wall = (b: { q: number; r: number }, kind: 'wall' | 'gate') => play({ method: 'POST', path: '/v1/villages/1/walls', body: { a: { q: home.q, r: home.r }, b: { q: b.q, r: b.r }, kind } });
  const march = async (target: { q: number; r: number }) => {
    const army = (await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: { q: target.q, r: target.r }, units: { spearman: 1 } } })).body.army;
    await play({ advance: 4 * MINUTE });
    if (army) await play({ method: 'POST', path: `/v1/armies/${army.id}/move`, body: { villageId: 1 } });
    await play({ advance: 4 * MINUTE });
  };

  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'barracks' } });
  await play({ set: { amounts: { wood: 9000, stone: 9000, grain: 9000, iron: 9000 } } });
  await play({ advance: 20 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 2 } });
  await play({ set: { amounts: { wood: 9000, stone: 9000, grain: 9000, iron: 9000 } } });

  // Raised tier by tier: each waits for the work before it.
  await wall(first!, 'wall');
  await wall(first!, 'wall');
  await play({ advance: 2 * MINUTE });
  await wall(first!, 'wall');
  await play({ advance: 3 * MINUTE });
  await wall(first!, 'wall');
  await play({ advance: 4 * MINUTE });
  await wall(first!, 'wall');
  await play({ method: 'GET', path: world });
  // Round it.
  await march(first!);

  // A gatehouse: the village's own pass through it; no wall where it stands.
  await wall(second!, 'gate');
  await wall(second!, 'wall');
  await play({ advance: 3 * MINUTE });
  await play({ method: 'GET', path: world });
  await march(second!);

  // Torn down: nothing comes back.
  await play({ method: 'POST', path: '/v1/villages/1/walls/tear', body: { a: { q: home.q, r: home.r }, b: { q: first!.q, r: first!.r } } });
  await play({ method: 'GET', path: world });

  // A river between two of the village's neighbours: a wall on each bank
  // (the second refused while it is being raised), one bank's torn down.
  const [x, y] = (() => {
    for (const p of edges) for (const q of edges) if (hexDistance(p, q) === 1 && !rivers.has(edgeKey(p, q))) return [p, q];
    throw new Error('No two neighbouring neighbours');
  })();
  await play({ set: { river: { a: { q: x!.q, r: x!.r }, b: { q: y!.q, r: y!.r } } } });
  const bankWall = (bank: { q: number; r: number }, kind: 'wall' | 'gate') =>
    play({ method: 'POST', path: '/v1/villages/1/walls', body: { a: { q: x!.q, r: x!.r }, b: { q: y!.q, r: y!.r }, kind, bank: { q: bank.q, r: bank.r } } });
  await bankWall(x!, 'wall');
  await bankWall(y!, 'gate');
  await bankWall(x!, 'wall');
  await play({ advance: 3 * MINUTE });
  await play({ method: 'GET', path: world });
  await play({ method: 'POST', path: '/v1/villages/1/walls/tear', body: { a: { q: x!.q, r: x!.r }, b: { q: y!.q, r: y!.r }, bank: { q: y!.q, r: y!.r } } });

  // Walled all round (the gatehouse too stands in a horde's way), and the
  // Holy City too.
  await play({ set: { amounts: { wood: 9000, stone: 9000, grain: 9000, iron: 9000 } } });
  for (const n of edges.filter((e) => e !== second)) await wall(n, 'wall');
  const city = hex(0, 0);
  for (const n of neighbors(city).filter((c) => passable(c.q, c.r) && !rivers.has(edgeKey(city, c)))) {
    await play({ method: 'POST', path: '/v1/villages/1/walls', body: { a: { q: 0, r: 0 }, b: { q: n.q, r: n.r }, kind: 'wall' } });
  }
  await play({ advance: 2 * MINUTE });
  const walled = await play({ method: 'GET', path: world });
  const spawnAt = new Date(walled.body.waves[0].spawnAt).getTime();
  await play({ advance: Math.max(0, spawnAt - now().getTime()) + MINUTE });
  const marching = (await play({ method: 'GET', path: world })).body;
  const arriveIn = new Date(marching.waves[0].arrivesAt).getTime() - now().getTime();
  await play({ advance: Math.max(MINUTE, arriveIn / 2) });
  await play({ method: 'GET', path: world });
  await play({ advance: Math.max(MINUTE, arriveIn / 2) + MINUTE });
  await play({ method: 'GET', path: world });
}, 60_000);
