// Field armies in a solo session: soldiers dismissed from the garrison; an
// army that holds a hex, is moved on, and marches back into the garrison
// with what grain it has left; one left out with no food that slows,
// loses men and starves; one disbanded where it stands.
import { neighbors, hex } from '../src/sim/hex.js';
import { MINUTE, scenario, scheduler } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Field', displayName: 'You', speed: 50, difficulty: 'normal' };

scenario('field-scenario.json', START, async ({ started, play }) => {
  const world = '/v1/worlds/-1';
  const home = started.villages[0] as { q: number; r: number };
  const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const passable = (q: number, r: number) => {
    const t = terrain.get(`${q},${r}`);
    return t !== undefined && t !== 'holy_city' && scheduler.data.terrain.terrain[t as keyof typeof scheduler.data.terrain.terrain].moveCost !== null;
  };
  const near = neighbors(hex(home.q, home.r)).filter((n) => passable(n.q, n.r));
  const [first, second] = [near[0]!, near[1]!];
  const army = (body: object) => play({ method: 'POST', path: '/v1/villages/1/armies', body });

  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'barracks' } });
  await play({ advance: 20 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 8 } });
  await play({ advance: 10 * MINUTE });
  // Dismissed: two go home to their farms; there are not 99 to send.
  await play({ method: 'POST', path: '/v1/villages/1/dismiss', body: { units: { spearman: 2 } } });
  await play({ method: 'POST', path: '/v1/villages/1/dismiss', body: { units: { spearman: 99 } } });
  await play({ method: 'POST', path: '/v1/villages/1/dismiss', body: { units: {} } });

  // An army holds a hex, can't be moved while marching, then moves on and
  // marches back into the garrison.
  const held = (await army({ orders: 'hold', target: { q: first.q, r: first.r }, units: { spearman: 2 } })).body.army;
  await play({ method: 'POST', path: `/v1/armies/${held.id}/move`, body: { target: { q: second.q, r: second.r } } });
  await play({ advance: 5 * MINUTE });
  await play({ method: 'POST', path: `/v1/armies/${held.id}/resupply`, body: {} });
  await play({ method: 'POST', path: `/v1/armies/${held.id}/move`, body: { target: { q: first.q, r: first.r } } });
  await play({ method: 'POST', path: `/v1/armies/${held.id}/move`, body: { target: { q: second.q, r: second.r } } });
  await play({ advance: 5 * MINUTE });
  await play({ method: 'POST', path: `/v1/armies/${held.id}/move`, body: { villageId: 1 } });
  await play({ advance: 5 * MINUTE });
  await play({ method: 'GET', path: world });

  // One disbanded where it stands; one left out until it starves.
  const gone = (await army({ orders: 'hold', target: { q: first.q, r: first.r }, units: { spearman: 1 } })).body.army;
  const lost = (await army({ orders: 'hold', target: { q: second.q, r: second.r }, units: { spearman: 3 } })).body.army;
  await play({ advance: 5 * MINUTE });
  await play({ method: 'POST', path: `/v1/armies/${gone.id}/disband`, body: {} });
  await play({ method: 'POST', path: `/v1/armies/${gone.id}/disband`, body: {} });
  // Out of food after a day (29 minutes at speed 50), losing men 8 game
  // hours later, gone after another day.
  await play({ advance: 30 * MINUTE });
  await play({ method: 'GET', path: world });
  await play({ advance: 12 * MINUTE });
  await play({ method: 'GET', path: world });
  await play({ advance: 20 * MINUTE });
  await play({ method: 'GET', path: world });
  await play({ method: 'POST', path: `/v1/armies/${lost.id}/move`, body: { villageId: 1 } });
});
