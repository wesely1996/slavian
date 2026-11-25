// Scouts searching for forgotten ruins in a solo session: searches refused
// for too few or too many scouts, or scouts the village doesn't have; one
// party sent out, another refused until the player's scouts have rested,
// then more, coming back with a new site or with nothing: away the
// longer the farther off the ruin they find, longest finding none.
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 5151, at: '2026-06-01T08:00:00.000Z', name: 'Ruins', displayName: 'You', speed: 50, difficulty: 'baron' };

scenario('ruins-scenario.json', START, async ({ play }) => {
  const search = (count: number) => play({ method: 'POST', path: '/v1/villages/1/scout/ruins', body: { count } });

  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'scout_lodge' } });
  await play({ advance: 20 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'scout', count: 5 } });
  await play({ advance: 20 * MINUTE });

  // Too few, too many, more than are home.
  await search(1);
  await search(7);
  await search(6);

  // One party out; no other until the scouts have rested (12 game hours
  // from when it set out), though they are back long before.
  await search(2);
  await search(3);
  await play({ method: 'GET', path: '/v1/worlds/-1' });
  await play({ advance: 5 * MINUTE });
  await search(3);
  await play({ method: 'GET', path: '/v1/worlds/-1' });
  await play({ advance: 10 * MINUTE });
  for (let i = 0; i < 4; i++) {
    await search(5);
    await play({ advance: 15 * MINUTE });
  }
  await play({ method: 'GET', path: '/v1/worlds/-1' });
  await play({ method: 'GET', path: '/v1/worlds/-1/notifications' });
});
