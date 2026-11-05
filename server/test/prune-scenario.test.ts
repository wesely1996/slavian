// Daily pruning in a solo session: an army clears the starter camp (a
// battle, a cleared camp, notices) and a caravan goes to the vault and back;
// a day and more later, the world has forgotten what is done and old, and
// what it took away still counts.
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Pruning', displayName: 'You', speed: 1, difficulty: 'normal' };
const HOUR = 60 * MINUTE;

scenario('prune-scenario.json', START, async ({ play }) => {
  const world = '/v1/worlds/-1';
  await play({ set: { garrison: { spearman: 12 } } });
  const view = (await play({ method: 'GET', path: world })).body;
  const camp = view.camps[0];
  if (camp) await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'clear', target: { q: camp.q, r: camp.r }, units: { spearman: 12 } } });
  await play({ advance: 4 * HOUR });
  await play({ method: 'GET', path: world });
  await play({ method: 'GET', path: `${world}/notifications` });
  // The first pruning, a day in: what ended within the day stays.
  await play({ advance: 21 * HOUR });
  await play({ method: 'GET', path: world });
  // The second: it is more than a day old now, and goes.
  await play({ advance: 24 * HOUR });
  await play({ method: 'GET', path: world });
  await play({ method: 'GET', path: `${world}/notifications` });
});
