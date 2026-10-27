// Generals in a solo session: refused without a Hero's Hall, recruited at
// one (and no more than it keeps), ready after a while; one rides with the
// hero to hold the hex before the village on the first horde's road, and
// falls when the horde breaks the army there; another is recruited in its
// place and dismissed.
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Generals', displayName: 'You', speed: 50, difficulty: 'normal' };

scenario('generals-scenario.json', START, async ({ started, now, play }) => {
  const at = (iso: string) => new Date(iso).getTime();
  const world = '/v1/worlds/-1';
  const spawnAt = at((started.waves as { spawnAt: string }[])[0]!.spawnAt);

  await play({ method: 'POST', path: '/v1/villages/1/generals', body: {} });
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c1', building: 'heroes_hall' } });
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'barracks' } });
  await play({ advance: 40 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/generals', body: {} });
  // Not here yet, and the Hall keeps only one.
  await play({ method: 'POST', path: '/v1/generals/1/move', body: { villageId: 1 } });
  await play({ method: 'POST', path: '/v1/villages/1/generals', body: {} });
  await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 5 } });
  await play({ advance: 5 * MINUTE });
  await play({ method: 'POST', path: '/v1/generals/1/move', body: { villageId: 1 } });
  await play({ method: 'GET', path: world });
  // Once the horde is on its way, hold the hex before the village.
  await play({ advance: spawnAt - now().getTime() + MINUTE });
  const first = (await play({ method: 'GET', path: world })).body.waves[0];
  const [hq, hr] = first.path.at(-2) as [number, number, number];
  await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: { q: hq, r: hr }, units: { spearman: 4 }, withHero: true, generalId: 1 } });
  await play({ method: 'POST', path: '/v1/generals/1/dismiss', body: {} });
  await play({ advance: at(first.arrivesAt) - now().getTime() + 3 * MINUTE });
  const after = (await play({ method: 'GET', path: world })).body;
  const army = after.armies.find((a: { orders: string; status: string }) => a.orders === 'hold' && a.status === 'stationed');
  if (army) await play({ method: 'POST', path: `/v1/armies/${army.id}/recall`, body: {} });
  await play({ advance: 30 * MINUTE });
  await play({ method: 'GET', path: world });
  // It fell with the beaten army: there is room for another, who is
  // dismissed while still on the way.
  await play({ method: 'POST', path: '/v1/generals/1/dismiss', body: {} });
  await play({ method: 'POST', path: '/v1/villages/1/generals', body: {} });
  await play({ method: 'POST', path: '/v1/generals/2/dismiss', body: {} });
  await play({ method: 'GET', path: world });
});
