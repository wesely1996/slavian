// The inbox in a solo session (docs/local-engine.md, part 5): builds
// finishing are summed up in the daily digest at the player's digest hour,
// then everything is marked read.
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T17:50:00.000Z', name: 'Letters', displayName: 'You', speed: 1, difficulty: 'normal' };

scenario('inbox-scenario.json', START, async ({ play }) => {
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'f6' } });
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'f0' } });
  await play({ advance: 9 * MINUTE });
  await play({ method: 'GET', path: '/v1/worlds/-1/notifications' });
  await play({ advance: 2 * MINUTE });
  await play({ method: 'GET', path: '/v1/worlds/-1/notifications' });
  await play({ method: 'POST', path: '/v1/worlds/-1/notifications/read', body: {} });
});
