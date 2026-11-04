// Daily map events in a solo session: a game day in, the first rises near
// the village; captives freed by an army that clears their camp (troops
// joining it, or goods carried home), a hard ruin explored, and events
// nobody goes to gone when their time is up, the next horde hating the
// more for it. Each one done brings a bounty home.
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Events', displayName: 'You', speed: 50, difficulty: 'normal' };
// A game day at speed 50.
const DAY = (24 * 60 * MINUTE) / 50;

scenario('events-scenario.json', START, async ({ play }) => {
  const world = '/v1/worlds/-1';
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'barracks' } });
  await play({ advance: 20 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 6 } });
  await play({ advance: 15 * MINUTE });

  // Each day's event, gone to by an army if there is one to spare.
  for (let day = 1; day <= 3; day++) {
    const view = (await play({ method: 'GET', path: world })).body;
    const captives = view.camps.find((c: { kind: string }) => c.kind === 'captives');
    const ruin = view.sites.find((s: { hard: boolean; status: string }) => s.hard && s.status === 'unexplored');
    const spearmen = view.villages[0].garrison.spearman ?? 0;
    if (captives && spearmen >= 3) {
      await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'clear', target: { q: captives.q, r: captives.r }, units: { spearman: spearmen } } });
    } else if (ruin && spearmen >= 3) {
      await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'explore', target: { q: ruin.q, r: ruin.r }, units: { spearman: spearmen } } });
    }
    await play({ advance: DAY });
  }
  await play({ method: 'GET', path: world });
  // Two days on, the events nobody went to are gone.
  await play({ advance: 2 * DAY });
  await play({ method: 'GET', path: world });

  // A strong army searches the next forbidding ruin to rise, for its bounty.
  await play({ set: { garrison: { spearman: 120, archer: 60 } } });
  for (let day = 0; day < 6; day++) {
    const view = (await play({ method: 'GET', path: world })).body;
    const ruin = view.sites.find((s: { hard: boolean; status: string }) => s.hard && s.status === 'unexplored');
    if (ruin) {
      await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'explore', target: { q: ruin.q, r: ruin.r }, units: { spearman: 120, archer: 60 } } });
      break;
    }
    await play({ advance: DAY });
  }
  await play({ advance: DAY });
  await play({ method: 'GET', path: world });
  await play({ method: 'GET', path: `${world}/notifications` });
});
