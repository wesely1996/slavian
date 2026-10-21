// Hordes setting out in a solo session (docs/local-engine.md, part 4): the
// front's leader taking their head, the march (spawn, route, target, the
// time of every step), the warning, and the next wave announced, sized to
// the garrison trained meanwhile. It stops short of the first arrival.
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Hordes', displayName: 'You', speed: 50, difficulty: 'normal' };

scenario('wave-scenario.json', START, async ({ started, now, play }) => {
  const at = (iso: string) => new Date(iso).getTime();
  const waves = started.waves as { spawnAt: string }[];

  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'barracks' } });
  await play({ advance: 20 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 8 } });
  // Just after the first horde sets out.
  await play({ advance: at(waves[0]!.spawnAt) - now().getTime() + MINUTE });
  const first = (await play({ method: 'GET', path: '/v1/worlds/-1' })).body.waves[0];
  // The horde comes within a minute of its target.
  await play({ advance: at(first.arrivesAt) - MINUTE - now().getTime() });
  await play({ method: 'GET', path: '/v1/worlds/-1' });
});
