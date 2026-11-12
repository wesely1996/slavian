// An undefended village in a solo session (docs/local-engine.md, part 4):
// the first hordes raid it and move on; a later one burns it to the
// ground, and the player's people find a refuge by the Holy City. Settlers
// in its garrison die with it, and the next ones are the cheaper for it.
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Ruins', displayName: 'You', speed: 50, difficulty: 'normal' };

scenario('raze-scenario.json', START, async ({ play }) => {
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'f6' } });
  await play({ set: { garrison: { settler: 2 }, bought: { settler: 5 } } });
  for (let i = 0; i < 16; i++) {
    await play({ advance: 30 * MINUTE });
    await play({ method: 'GET', path: '/v1/worlds/-1' });
  }
});
