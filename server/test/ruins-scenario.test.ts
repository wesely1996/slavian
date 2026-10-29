// Scouts searching for forgotten ruins in a solo session: searches refused
// for too few or too many scouts, or scouts the village doesn't have; a
// few sent out, coming back with a new site or with nothing.
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 5151, at: '2026-06-01T08:00:00.000Z', name: 'Ruins', displayName: 'You', speed: 50, difficulty: 'normal' };

scenario('ruins-scenario.json', START, async ({ play }) => {
  const search = (count: number) => play({ method: 'POST', path: '/v1/villages/1/scout/ruins', body: { count } });

  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'scout_lodge' } });
  await play({ advance: 20 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'scout', count: 10 } });
  await play({ advance: 20 * MINUTE });

  // Too few, too many, more than are home.
  await search(1);
  await search(25);
  await search(12);

  // Two parties out at once; then three more, one after the other.
  await search(2);
  await search(6);
  await play({ method: 'GET', path: '/v1/worlds/-1' });
  await play({ advance: 5 * MINUTE });
  await play({ method: 'GET', path: '/v1/worlds/-1' });
  for (let i = 0; i < 3; i++) {
    await search(8);
    await play({ advance: 5 * MINUTE });
  }
  await play({ method: 'GET', path: '/v1/worlds/-1' });
  await play({ method: 'GET', path: '/v1/worlds/-1/notifications' });
});
