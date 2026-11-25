// The Leshen, the wrath of nature, in a solo session (events.json leshen),
// as a forest set alight may wake him: he rises with beasts of the North
// two hexes from the village, marches on it like the Avatar of Černobog and
// falls to its garrison: the great bounty for every member, a Svarog's
// Ember for the player, and the North hates the more.
import { hex, hexDistance } from '../src/sim/hex.js';
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Leshen', displayName: 'You', speed: 50, difficulty: 'baron' };

scenario('leshen-scenario.json', START, async ({ started, play }) => {
  const world = '/v1/worlds/-1';
  const home = hex(started.villages[0].q, started.villages[0].r);
  const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const taken = new Set<string>([
    ...started.sites.map((s: { q: number; r: number }) => `${s.q},${s.r}`),
    ...started.camps.map((c: { q: number; r: number }) => `${c.q},${c.r}`),
  ]);
  const ashes = [...terrain.keys()]
    .map((k) => k.split(',').map(Number) as [number, number])
    .map(([q, r]) => hex(q, r))
    .find((c) => terrain.get(`${c.q},${c.r}`) === 'plains' && hexDistance(c, home) === 2 && !taken.has(`${c.q},${c.r}`))!;

  await play({ set: { garrison: { spearman: 3000 }, leshen: { q: ashes.q, r: ashes.r } } });
  await play({ advance: MINUTE });
  await play({ method: 'GET', path: world });
  await play({ advance: 10 * MINUTE });
  await play({ method: 'GET', path: world });
  for (let i = 0; i < 6; i++) {
    await play({ advance: 10 * MINUTE });
    await play({ method: 'GET', path: world });
  }
  await play({ method: 'GET', path: '/v1/worlds/-1/notifications' });
});
