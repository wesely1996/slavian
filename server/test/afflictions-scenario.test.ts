// Burn and poison (battle.json afflictions) in a solo session: the
// Blacksmith forges fire arrows for the archers (refused for a unit whose
// blows carry poison already, and for a unit it doesn't serve); then a
// garrison of archers and poison archers holds against the first horde,
// burning and poisoning it round by round (the battle carries both into the
// next round), and an army of them raids the North, where the same carries
// from round to round of each battle.
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Afflictions', displayName: 'You', speed: 50, difficulty: 'baron' };
// A game hour at speed 50.
const HOUR = (60 * MINUTE) / 50;

scenario('afflictions-scenario.json', START, async ({ started, now, play }) => {
  const world = '/v1/worlds/-1';
  const at = (iso: string) => new Date(iso).getTime();
  const smith = (unit: string, line: string) => play({ method: 'POST', path: '/v1/villages/1/smith', body: { unit, line } });
  await play({ set: { plots: { c2: { building: 'blacksmith', level: 10 } }, amounts: { wood: 9000, stone: 9000, grain: 9000, iron: 9000 } } });
  // Poison archers poison already; spearmen don't shoot fire arrows.
  await smith('poison_archer', 'poison');
  await smith('spearman', 'burn');
  await smith('archer', 'burn');
  await play({ advance: 6 * HOUR });
  await smith('spearman', 'poison');
  await play({ advance: 6 * HOUR });
  await play({ method: 'GET', path: world });

  // The first horde meets archers with fire arrows, poison archers and
  // spearmen with poisoned blades.
  await play({ set: { garrison: { spearman: 12, archer: 10, poison_archer: 8 } } });
  const spawnAt = at((started.waves as { spawnAt: string }[])[0]!.spawnAt);
  await play({ advance: spawnAt - now().getTime() + MINUTE });
  const first = (await play({ method: 'GET', path: world })).body.waves[0];
  await play({ advance: at(first.arrivesAt) - now().getTime() + 1_000 });
  await play({ method: 'GET', path: world });
  for (let i = 0; i < 3; i++) {
    await play({ advance: 10 * MINUTE });
    await play({ method: 'GET', path: world });
  }

  // A raid on the North: each battle burns and poisons from round to round.
  await play({ set: { garrison: { spearman: 20, archer: 12, poison_archer: 10 } } });
  await play({ method: 'POST', path: '/v1/villages/1/raids', body: { front: 'north', depth: 1, units: { spearman: 20, archer: 12, poison_archer: 10 } } });
  for (let i = 0; i < 4; i++) {
    await play({ advance: 3 * HOUR });
    await play({ method: 'GET', path: world });
  }
  await play({ advance: 12 * HOUR });
  await play({ method: 'GET', path: world });
});
