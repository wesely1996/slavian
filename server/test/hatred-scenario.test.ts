// A horde's hatred in a solo session: the hero ambushes the next horde
// (each ambush holds it up and makes it hate the more, and the next ambush
// on it is riskier and worth more XP); the hating horde comes on stronger,
// and when it is over leaves camps behind for its hatred.
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Hatred', displayName: 'You', speed: 50, difficulty: 'normal' };

scenario('hatred-scenario.json', START, async ({ started, now, play }) => {
  const world = '/v1/worlds/-1';
  const firstFront = (started.waves as { front: string }[])[0]!.front;
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'barracks' } });
  await play({ advance: 20 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 6 } });

  // The hero takes every ambush on the first horde's front it is offered
  // while that horde is yet to set out.
  let ambushes = 0;
  for (let i = 0; i < 16 && ambushes < 3; i++) {
    const body = (await play({ method: 'GET', path: world })).body;
    const first = body.waves[0];
    if (first.status !== 'scheduled') break;
    const hero = body.heroes[0];
    const offer = hero?.status === 'home' ? hero.offers.find((o: { kind: string; front: string }) => o.kind === 'ambush' && o.front === firstFront) : undefined;
    if (offer) {
      await play({ method: 'POST', path: `${world}/hero/quest`, body: { offer: offer.id } });
      ambushes++;
    }
    await play({ advance: 10 * MINUTE });
  }
  await play({ method: 'GET', path: world });

  // The horde comes on, hating; when it is over, its camps rise.
  const first = (await play({ method: 'GET', path: world })).body.waves[0];
  const spawn = new Date(first.spawnAt).getTime();
  await play({ advance: Math.max(MINUTE, spawn - now().getTime() + 5 * MINUTE) });
  await play({ method: 'GET', path: world });
  await play({ advance: 60 * MINUTE });
  await play({ method: 'GET', path: world });
  await play({ advance: 120 * MINUTE });
  await play({ method: 'GET', path: world });
});
