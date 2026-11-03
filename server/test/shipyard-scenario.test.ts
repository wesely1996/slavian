// A shipyard in a solo session: a daily event on a river bank the village
// pays for over a few days; while the boat is built, raiders strike and an
// army standing there fights them (or work is lost); once it is done, an
// army marching along the river goes three times as fast.
import { hex, hexDistance } from '../src/sim/hex.js';
import { riverLanes } from '../src/sim/land.js';
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Shipyard', displayName: 'You', speed: 50, difficulty: 'normal' };
// A game day at speed 50.
const DAY = (24 * 60 * MINUTE) / 50;
const HOUR = DAY / 24;

type View = Record<string, any>;

scenario('shipyard-scenario.json', START, async ({ play }) => {
  const world = '/v1/worlds/-1';
  const view = async (): Promise<View> => (await play({ method: 'GET', path: world })).body;
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'barracks' } });
  await play({ advance: 20 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 6 } });
  await play({ advance: 15 * MINUTE });

  // Days go by until boatwrights wait somewhere; the village sends what it
  // can each day until the boat is paid for, and the spearmen go to stand
  // guard (they are there before the first raiders).
  let shipyard: View | undefined;
  for (let day = 1; day <= 12; day++) {
    await play({ advance: DAY });
    shipyard = (await view()).shipyards.find((s: View) => s.status !== 'done');
    if (shipyard) {
      await play({ method: 'POST', path: `/v1/villages/1/shipyards/${shipyard.id}` });
      shipyard = (await view()).shipyards.find((s: View) => s.id === shipyard!.id);
      if (shipyard?.status === 'building') break;
    }
  }
  if (!shipyard || shipyard.status !== 'building') throw new Error('no shipyard was begun');
  // A second payment is turned away: it is paid for.
  await play({ method: 'POST', path: `/v1/villages/1/shipyards/${shipyard.id}` });

  const spearmen = (await view()).villages[0].garrison.spearman ?? 0;
  await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: { q: shipyard.q, r: shipyard.r }, units: { spearman: spearmen } } });

  // Raids come every 8 hours until the boat is done: the spearmen drive
  // off the first, then are called home, and the next burn work.
  for (let i = 0; i < 6; i++) {
    await play({ advance: 8 * HOUR });
    if (i === 0) await play({ method: 'POST', path: '/v1/armies/1/recall' });
    const now = (await view()).shipyards.find((s: View) => s.id === shipyard!.id);
    if (now.status === 'done') break;
  }
  const done = (await view()).shipyards.find((s: View) => s.id === shipyard!.id);
  if (done.status !== 'done') await play({ advance: 2 * DAY });

  // Along the river now: the army still standing there (or what is left of
  // it, sent out again) marches down it, to the bank hex furthest from the
  // shipyard (up to 6 hexes off).
  let state = await view();
  let army = state.armies.find((a: View) => a.status === 'stationed');
  const left = state.villages[0].garrison.spearman ?? 0;
  if (!army && left > 0) {
    await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: { q: shipyard.q, r: shipyard.r }, units: { spearman: left } } });
    await play({ advance: 4 * HOUR });
    state = await view();
    army = state.armies.find((a: View) => a.status === 'stationed');
  }
  if (army) {
    const rivers = state.map.rivers.map(([aq, ar, bq, br]: number[]) => ({ a: hex(aq!, ar!), b: hex(bq!, br!) }));
    const [aq, ar, bq, br] = done.edge;
    const banks = new Set(riverLanes(rivers, { a: hex(aq, ar), b: hex(bq, br) }).flatMap((k) => k.split('|')));
    const here = hex(shipyard.q, shipyard.r);
    const far = [...banks]
      .map((k) => hex(...(k.split(',').map(Number) as [number, number])))
      .filter((h) => hexDistance(h, here) <= 6)
      .sort((x, y) => hexDistance(y, here) - hexDistance(x, here) || x.q - y.q || x.r - y.r)[0]!;
    await play({ method: 'POST', path: `/v1/armies/${army.id}/move`, body: { target: far } });
  }
  await play({ advance: 4 * HOUR });
  await view();
});
