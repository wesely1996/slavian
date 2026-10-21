// Standing orders and the end of a run in a solo session
// (docs/local-engine.md, part 5): orders placed, refused, run and
// cancelled; the bridge refusing what it can't take; then, jumped ahead to
// the Ritual Arch with everything but the torc, the torc forged, the last
// stage raised, Ritual Night's hordes, and the run's end.
import { MINUTE, scenario, scheduler } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Arch', displayName: 'You', speed: 50, difficulty: 'normal' };

scenario('endgame-scenario.json', START, async ({ now, play }) => {
  const world = '/v1/worlds/-1';
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'barracks' } });
  await play({ advance: 20 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/orders', body: { kind: 'train', unit: 'spearman', batch: 2, target: 4 } });
  await play({ method: 'POST', path: '/v1/villages/1/orders', body: { kind: 'train', unit: 'spearman', batch: 3, target: 6 } });
  await play({ method: 'POST', path: '/v1/villages/1/orders', body: { kind: 'train', unit: 'spearman', batch: 9, target: 2 } });
  await play({ method: 'POST', path: '/v1/villages/1/orders', body: { kind: 'surplus', share: 0.5 } });
  await play({ method: 'POST', path: '/v1/villages/1/orders', body: { kind: 'surplus', share: 0.1 } });
  await play({ method: 'POST', path: '/v1/villages/1/orders', body: { kind: 'rebuild' } });
  await play({ method: 'POST', path: '/v1/villages/1/orders/2/cancel', body: {} });
  await play({ method: 'POST', path: '/v1/villages/1/orders/9/cancel', body: {} });
  await play({ advance: 30 * MINUTE });
  await play({ method: 'GET', path: world });
  await play({ method: 'POST', path: `${world}/bridge/donate`, body: { resources: { wood: 100, stone: 0, grain: 0, iron: 0 }, embers: 0 } });
  await play({ method: 'POST', path: `${world}/bridge/donate`, body: { resources: { wood: 0, stone: 0, grain: 0, iron: 0 }, embers: 5 } });
  await play({ method: 'POST', path: `${world}/bridge/ritual`, body: {} });
  // Jump ahead: the Ritual Arch paid for, its Ember in, only the torc missing.
  const arch = scheduler.data.bridge.stages.length - 1;
  await play({
    set: {
      bridge: {
        stage: arch,
        donated: scheduler.data.bridge.stages[arch]!.cost,
        embers: scheduler.data.bridge.stages[arch]!.embers,
        quests: {},
        stageStartedAt: now().toISOString(),
        sanctityAtStart: 100,
        status: 'open',
        raisedAt: null,
      },
      embers: scheduler.data.bridge.ritualEmbers,
    },
  });
  await play({ method: 'POST', path: `${world}/bridge/ritual`, body: {} });
  for (let i = 0; i < 8; i++) {
    await play({ advance: 10 * MINUTE });
    await play({ method: 'GET', path: world });
  }
});
