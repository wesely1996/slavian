// Cultists of Černobog in a solo session (events.json ritual), as the rare
// daily event would bring them: a weak army driven off from their circle
// brings the ritual's end nearer, soldier by soldier; a strong one scatters
// them, for the event's bounty and a hidden achievement. A second circle
// left alone finishes its ritual: the Avatar rises where it stood, marches
// on the village like a horde, and falls to its garrison: the great bounty
// for every member, and two more hidden achievements.
import { hex, hexDistance } from '../src/sim/hex.js';
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Cultists', displayName: 'You', speed: 50, difficulty: 'baron' };

scenario('cultists-scenario.json', START, async ({ started, play }) => {
  const world = '/v1/worlds/-1';
  const home = hex(started.villages[0].q, started.villages[0].r);
  const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const taken = new Set<string>([
    ...started.sites.map((s: { q: number; r: number }) => `${s.q},${s.r}`),
    ...started.camps.map((c: { q: number; r: number }) => `${c.q},${c.r}`),
  ]);
  const open = [...terrain.keys()]
    .map((k) => k.split(',').map(Number) as [number, number])
    .map(([q, r]) => hex(q, r))
    .filter((c) => terrain.get(`${c.q},${c.r}`) === 'plains' && hexDistance(c, home) === 2 && !taken.has(`${c.q},${c.r}`));
  const [first, second] = open;
  const front = started.map.activeFronts[0] as string;
  const guards = front === 'north' ? { grey_wolf: 8 } : { zealot: 8 };

  await play({ set: { garrison: { spearman: 40 }, ritual: { q: first!.q, r: first!.r, front, guards } } });
  await play({ method: 'GET', path: world });
  // Too few: driven off, and every one of them who fell feeds the ritual.
  await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'clear', target: { q: first!.q, r: first!.r }, units: { spearman: 2 } } });
  await play({ advance: 3 * MINUTE });
  await play({ method: 'GET', path: world });
  // Enough: the circle is broken.
  await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'clear', target: { q: first!.q, r: first!.r }, units: { spearman: 30 } } });
  await play({ advance: 3 * MINUTE });
  await play({ method: 'GET', path: world });

  // Left alone, the second circle finishes its ritual.
  await play({ set: { garrison: { spearman: 2000 }, ritual: { q: second!.q, r: second!.r, front, guards } } });
  await play({ advance: 44 * MINUTE });
  await play({ method: 'GET', path: world });
  await play({ advance: 30 * MINUTE });
  await play({ method: 'GET', path: world });
  await play({ method: 'GET', path: '/v1/worlds/-1/notifications' });
});
