// The Blacksmith in a solo session (data/smithing.json): forging is refused
// without a Blacksmith, for a unit or line that doesn't exist, and while
// another improvement is under way; the Spearman's sharper arms (level 1)
// finish and show in the player's bonuses; level 2 waits for a Blacksmith
// of level 5; a better harness makes the same march arrive sooner.
import { hex, hexDistance } from '../src/sim/hex.js';
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Forge', displayName: 'You', speed: 50, difficulty: 'baron' };
const HOUR = (60 * MINUTE) / 50;

type View = Record<string, any>;

scenario('smithing-scenario.json', START, async ({ started, play }) => {
  const world = '/v1/worlds/-1';
  const view = async (): Promise<View> => (await play({ method: 'GET', path: world })).body;
  const smith = (unit: string, line: string) => play({ method: 'POST', path: '/v1/villages/1/smith', body: { unit, line } });
  // No Blacksmith yet.
  await smith('spearman', 'attack');
  await play({ set: { plots: { c2: { building: 'blacksmith', level: 1 } }, amounts: { wood: 5000, stone: 5000, grain: 5000, iron: 5000 } } });
  await smith('dragon', 'attack');
  await smith('settler', 'attack');
  await smith('spearman', 'cunning');
  await smith('spearman', 'attack');
  // One at a time.
  await smith('archer', 'defense');
  await view();
  await play({ advance: 3 * HOUR });
  await view();
  // Level 2 needs a Blacksmith of level 5.
  await smith('spearman', 'attack');
  await play({ set: { plots: { c2: { building: 'blacksmith', level: 5 } } } });
  await smith('spearman', 'attack');
  await play({ advance: 6 * HOUR });
  await view();

  // The same march, before and after a better harness.
  const home = hex(started.villages[0].q, started.villages[0].r);
  const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const target = [...terrain.entries()]
    .filter(([, t]) => t === 'plains')
    .map(([k]) => hex(...(k.split(',').map(Number) as [number, number])))
    .filter((c) => hexDistance(c, home) === 3)
    .sort((a, b) => a.q - b.q || a.r - b.r)[0]!;
  await play({ set: { garrison: { spearman: 20 } } });
  const march = () => play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: { q: target.q, r: target.r }, units: { spearman: 10 } } });
  await march();
  await smith('spearman', 'speed');
  await play({ advance: 4 * HOUR });
  await march();
  await view();
});
