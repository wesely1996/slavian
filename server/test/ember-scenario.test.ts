// Svarog's Embers in a solo session (PLAN.md M5 step 27): a bridge stage
// opens wanting an Ember the group lacks, a lair rises by the road of the
// North's latest horde (though the stage has no lair quest), and clearing
// it brings the Ember (a lair always holds one while the bridge lacks one;
// on this map its own chance would have missed).
import { MINUTE, scenario, scheduler } from './scenario.js';

const START = { seed: 4244, at: '2026-06-01T08:00:00.000Z', name: 'Embers', displayName: 'You', speed: 50, difficulty: 'normal' };

scenario('ember-scenario.json', START, async ({ started, now, play }) => {
  const world = '/v1/worlds/-1';
  const data = scheduler.data;
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'barracks' } });
  await play({ advance: 20 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 8 } });
  // Just after a horde of the North sets out: a lair rises by its road.
  const north = (started.waves as { front: string; spawnAt: string }[]).find((w) => w.front === 'north')!;
  await play({ advance: new Date(north.spawnAt).getTime() - now().getTime() + MINUTE });
  // Jump ahead: the Oak Piers all but paid (its quest done, its Ember in),
  // the last wood waiting in the vault, and the group without an Ember.
  const piers = data.bridge.stages[1]!;
  await play({
    set: {
      bridge: {
        stage: 1,
        donated: { ...piers.cost, wood: piers.cost.wood - 10 },
        embers: piers.embers,
        quests: { lair: now().toISOString() },
        stageStartedAt: now().toISOString(),
        sanctityAtStart: 100,
        status: 'open',
        raisedAt: null,
      },
      embers: 0,
      vault: { wood: 10, stone: 0, grain: 0, iron: 0 },
    },
  });
  await play({ method: 'POST', path: `${world}/bridge/donate`, body: { resources: { wood: 10, stone: 0, grain: 0, iron: 0 }, embers: 0 } });
  // Raised: the Iron Span wants an Ember the group lacks.
  await play({ advance: (data.bridge.buildHours * 60 * MINUTE) / START.speed + MINUTE });
  const view = (await play({ method: 'GET', path: world })).body;
  const lair = view.camps.find((c: { kind: string }) => c.kind === 'lair');
  // Every spearman at home, with the hero.
  const spearmen = view.villages[0].garrison.spearman;
  await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'clear', target: { q: lair.q, r: lair.r }, units: { spearman: spearmen }, withHero: true } });
  for (let i = 0; i < 6; i++) {
    await play({ advance: 10 * MINUTE });
    await play({ method: 'GET', path: world });
  }
});
