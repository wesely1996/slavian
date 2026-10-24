// A village holds against a horde in a solo session (docs/local-engine.md,
// part 4): the horde arrives, walls and garrison fight it round by round,
// it breaks; fear stays behind, a camp rises near its road and grows, its
// leader is wounded and bears a grudge, the hero gains from it, and the
// hospital puts some of the fallen back on their feet. The next
// horde builds a ram, breaches the walls, raids the village and marches on
// to the Holy City, whose guard beats it.
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Battles', displayName: 'You', speed: 50, difficulty: 'normal' };

scenario('battle-scenario.json', START, async ({ started, now, play }) => {
  const at = (iso: string) => new Date(iso).getTime();
  const spawnAt = at((started.waves as { spawnAt: string }[])[0]!.spawnAt);

  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'barracks' } });
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { building: 'wall' } });
  await play({ advance: 20 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 8 } });
  await play({ advance: spawnAt - now().getTime() - 10 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c3', building: 'hospital' } });
  await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 6 } });
  await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'archer', count: 2 } });
  await play({ advance: 11 * MINUTE });
  const first = (await play({ method: 'GET', path: '/v1/worlds/-1' })).body.waves[0];
  // The first round, then the rest.
  await play({ advance: at(first.arrivesAt) - now().getTime() + 1_000 });
  await play({ method: 'GET', path: '/v1/worlds/-1' });
  await play({ advance: 2 * MINUTE });
  await play({ method: 'GET', path: '/v1/worlds/-1' });
  // The camp grows; the next horde, from the south, comes and goes.
  await play({ advance: 30 * MINUTE });
  await play({ method: 'GET', path: '/v1/worlds/-1' });
  const second = (await play({ advance: 30 * MINUTE }), await play({ method: 'GET', path: '/v1/worlds/-1' })).body.waves[0];
  await play({ advance: at(second.arrivesAt) - now().getTime() + 20 * MINUTE });
  await play({ method: 'GET', path: '/v1/worlds/-1' });
});
