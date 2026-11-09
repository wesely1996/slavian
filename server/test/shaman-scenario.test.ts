// Shamans in a solo session: refused before the Hospital stands at level 2,
// then trained there; an army with Shamans storms the starter camp, and
// those of its fallen they heal get up again (raids, guardians and the
// village's own battles heal the same way).
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Shamans', displayName: 'You', speed: 10, difficulty: 'normal' };

scenario('shaman-scenario.json', START, async ({ play }) => {
  const world = '/v1/worlds/-1';
  const build = (body: object) => play({ method: 'POST', path: '/v1/villages/1/build', body });
  const train = (unit: string, count: number) => play({ method: 'POST', path: '/v1/villages/1/train', body: { unit, count } });
  await build({ plot: 'c2', building: 'hospital' });
  await train('shaman', 1);
  await play({ advance: 60 * MINUTE });
  await build({ plot: 'c2' });
  await build({ plot: 'c3', building: 'barracks' });
  await play({ advance: 120 * MINUTE });
  await train('shaman', 4);
  await train('spearman', 8);
  await play({ advance: 60 * MINUTE });
  const view = (await play({ method: 'GET', path: world })).body;
  const camp = view.camps[0] as { q: number; r: number } | undefined;
  const garrison = view.villages[0].garrison as Record<string, number>;
  if (camp) {
    await play({
      method: 'POST',
      path: '/v1/villages/1/armies',
      body: { orders: 'clear', target: { q: camp.q, r: camp.r }, units: { spearman: garrison.spearman ?? 0, shaman: garrison.shaman ?? 0 } },
    });
  }
  await play({ advance: 120 * MINUTE });
  await play({ method: 'GET', path: world });
});
