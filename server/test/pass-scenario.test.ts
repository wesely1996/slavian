// Mountain passes in a solo session: a road cut into a mountain beside the
// village costs and takes field.json road.mountainFactor times as much;
// once it stands, an army marches through the mountain along it (slowly),
// though none may stop there; a road into a lake is still refused.
import { hex, hexDistance, neighbors } from '../src/sim/hex.js';
import { MINUTE, scenario, scheduler } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Passes', displayName: 'You', speed: 50, difficulty: 'normal' };

scenario('pass-scenario.json', START, async ({ started, play }) => {
  const world = '/v1/worlds/-1';
  const home = hex(started.villages[0].q, started.villages[0].r);
  const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const kind = (h: { q: number; r: number }) => terrain.get(`${h.q},${h.r}`);
  const open = (h: { q: number; r: number }) => {
    const t = kind(h);
    return t !== undefined && t !== 'holy_city' && scheduler.data.terrain.terrain[t as keyof typeof scheduler.data.terrain.terrain].moveCost !== null;
  };
  // A mountain near the village with open land on two sides.
  const cells = [...terrain.keys()].map((k) => k.split(',').map(Number) as [number, number]).map(([q, r]) => hex(q, r));
  const mountain = cells
    .filter((c) => kind(c) === 'mountain' && hexDistance(c, home) <= 3)
    .sort((a, b) => hexDistance(a, home) - hexDistance(b, home))
    .find((c) => neighbors(c).filter(open).length >= 2)!;
  const [near, far] = neighbors(mountain)
    .filter(open)
    .sort((a, b) => hexDistance(a, home) - hexDistance(b, home));
  const road = (a: { q: number; r: number }, b: { q: number; r: number }) =>
    play({ method: 'POST', path: '/v1/villages/1/roads', body: { a: { q: a.q, r: a.r }, b: { q: b.q, r: b.r } } });

  await play({ set: { garrison: { spearman: 4 }, amounts: { wood: 5000, stone: 5000, grain: 5000, iron: 5000 } } });
  // Into the mountain: three times the price and the time.
  await road(near!, mountain);
  await road(mountain, far!);
  await play({ method: 'GET', path: world });
  // No army may stop on the mountain, road or not.
  await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: { q: mountain.q, r: mountain.r }, units: { spearman: 1 } } });
  await play({ advance: 5 * MINUTE });
  await play({ method: 'GET', path: world });
  // Through the pass to the far side.
  await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: { q: far!.q, r: far!.r }, units: { spearman: 2 } } });
  await play({ advance: 3 * MINUTE });
  await play({ method: 'GET', path: world });
  // The pass, improved: dearer again, three times over.
  await road(near!, mountain);
  await play({ advance: 5 * MINUTE });
  await play({ method: 'GET', path: world });
});
