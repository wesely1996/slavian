// Merchant caravans in a solo session: one sent to the Holy City trades
// along the road and brings home 20 of each resource for every hex out and
// back; the player's merchants then rest (12 game hours at a first-level
// Caravan Yard, less with every level, never under 8.5). Refused: a second
// one while they rest, one to the sender itself, one to no such village,
// and one without a Caravan Yard.
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 5151, at: '2026-06-01T08:00:00.000Z', name: 'Merchants', displayName: 'You', speed: 50, difficulty: 'baron' };

scenario('merchant-scenario.json', START, async ({ play }) => {
  const merchant = (destinationVillageId: number | null) =>
    play({ method: 'POST', path: '/v1/villages/1/caravans/merchant', body: { destinationVillageId } });
  // No Caravan Yard yet, and a body without a destination.
  await merchant(null);
  await play({ method: 'POST', path: '/v1/villages/1/caravans/merchant', body: {} });
  await play({ set: { plots: { c2: { building: 'caravan_yard', level: 1 } } } });
  await merchant(1);
  await merchant(999);
  await merchant(null);
  // Resting: refused until the cooldown is over.
  await merchant(null);
  await play({ method: 'GET', path: '/v1/worlds/-1' });
  await play({ advance: 10 * MINUTE });
  await play({ method: 'GET', path: '/v1/worlds/-1' });
  await play({ advance: 5 * MINUTE });
  await play({ method: 'GET', path: '/v1/worlds/-1' });
  // A higher yard rests them less.
  await play({ set: { plots: { c2: { building: 'caravan_yard', level: 10 } } } });
  await merchant(null);
  await play({ method: 'GET', path: '/v1/worlds/-1' });
  await play({ advance: 15 * MINUTE });
  await play({ method: 'GET', path: '/v1/worlds/-1' });
});
