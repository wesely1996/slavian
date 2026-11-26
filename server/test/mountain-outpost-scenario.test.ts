// An outpost through a mountain pass in a solo session: a road cut into the
// mountain beside the village, an outpost claimed on the mountain, which
// gathers twice the share a road's level adds (field.json
// road.passOutpostFactor); improved, the pass adds twice its new level's
// share.
import { hex, hexDistance, neighbors } from '../src/sim/hex.js';
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 4201, at: '2026-06-01T08:00:00.000Z', name: 'Pass outpost', displayName: 'You', speed: 50, difficulty: 'baron' };

scenario('mountain-outpost-scenario.json', START, async ({ started, play }) => {
  const world = '/v1/worlds/-1';
  const home = hex(started.villages[0].q, started.villages[0].r);
  const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const mountain = neighbors(home)
    .filter((n) => terrain.get(`${n.q},${n.r}`) === 'mountain' && hexDistance(n, hex(0, 0)) > 0)
    .sort((a, b) => a.q - b.q || a.r - b.r)[0];
  if (!mountain) throw new Error('no mountain beside the village');
  const road = () => play({ method: 'POST', path: '/v1/villages/1/roads', body: { a: { q: home.q, r: home.r }, b: { q: mountain.q, r: mountain.r } } });

  await play({ set: { amounts: { wood: 5000, stone: 5000, grain: 5000, iron: 5000 } } });
  await road();
  await play({ advance: 5 * MINUTE });
  // Claimed once the pass stands: its road link counts twice.
  await play({ method: 'POST', path: '/v1/villages/1/outposts', body: { q: mountain.q, r: mountain.r } });
  await play({ advance: 2 * MINUTE });
  await play({ method: 'GET', path: world });
  // The pass improved: the outpost's link grows with it, still twice.
  await road();
  await play({ advance: 5 * MINUTE });
  await play({ method: 'GET', path: world });
});
