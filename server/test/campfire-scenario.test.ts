// Burning a bandit camp in a solo session (camps.json burnt): a wood planted
// two hexes from the village, a camp of the South on it; clearing land
// there is refused, but a fire may be set on it. The camp burns, half to
// all of its troops flee at once as a small horde from where it stood on
// the village, and the South hates the more; the garrison meets them.
import { hex, hexDistance } from '../src/sim/hex.js';
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Campfire', displayName: 'You', speed: 50, difficulty: 'baron' };
// A game hour at speed 50.
const HOUR = (60 * MINUTE) / 50;

scenario('campfire-scenario.json', START, async ({ started, play }) => {
  const world = '/v1/worlds/-1';
  const home = hex(started.villages[0].q, started.villages[0].r);
  const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const taken = new Set<string>([
    ...started.sites.map((s: { q: number; r: number }) => `${s.q},${s.r}`),
    ...started.camps.map((c: { q: number; r: number }) => `${c.q},${c.r}`),
  ]);
  const cell = [...terrain.entries()]
    .filter(([k, t]) => t === 'plains' && !taken.has(k))
    .map(([k]) => hex(...(k.split(',').map(Number) as [number, number])))
    .filter((c) => hexDistance(c, home) === 2)
    .sort((a, b) => a.q - b.q || a.r - b.r)[0]!;
  const work = (action: string) => play({ method: 'POST', path: '/v1/villages/1/terraform', body: { q: cell.q, r: cell.r, action } });

  await play({ set: { amounts: { wood: 5000, stone: 5000, grain: 20000, iron: 5000 }, garrison: { spearman: 30, archer: 10 } } });
  await work('plant');
  await play({ advance: 17 * HOUR });
  await play({ set: { camp: { q: cell.q, r: cell.r, kind: 'bandit', front: 'south', units: { zealot: 10, crossbowman: 5 } } } });
  // Nothing else can be done where a camp stands; fire can.
  await work('clear');
  await work('burn');
  await play({ method: 'GET', path: world });
  // They march on the village and meet the garrison.
  for (let i = 0; i < 6; i++) {
    await play({ advance: HOUR });
    await play({ method: 'GET', path: world });
  }
  await play({ advance: 30 * MINUTE });
  await play({ method: 'GET', path: world });
});
