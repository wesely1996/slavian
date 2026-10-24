// The village rules in a solo session (docs/local-engine.md): builds, a
// full queue, training before and after the barracks, the stance, outposts
// (too poor, out of range, claimed, abandoned too early and then on time),
// renaming, claiming rewards, too many units, the walls and a tower slot,
// peaceful hours, and waits for the clock. Then the market (a trade, and
// gear the hero doesn't have), tearing buildings down (and what can't be),
// a second storehouse and a booster that needs its field higher.
import { hexDistance, neighbors, hex } from '../src/sim/hex.js';
import { MINUTE, scenario, scheduler, type Step } from './scenario.js';

const START = { seed: 777, at: '2026-06-01T08:00:00.000Z', name: 'Villages', displayName: 'You', speed: 10, difficulty: 'normal' };

scenario('village-scenario.json', START, async ({ started, play }) => {
  // An outpost hex: the first neighbour of the village (in hex order)
  // with something to gather and no site on it.
  const home = started.villages[0];
  const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const yields = scheduler.data.buildings.buildings.outpost!.yields ?? {};
  const outpost = neighbors(hex(home.q, home.r)).find((n) => yields[terrain.get(`${n.q},${n.r}`) as keyof typeof yields] && !started.sites.some((s: { q: number; r: number }) => s.q === n.q && s.r === n.r) && hexDistance(n, hex(0, 0)) > 0)!;

  const steps: Step[] = [
    { method: 'POST', path: '/v1/villages/1/build', body: { plot: 'f6' } },
    { method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'barracks' } },
    // Three more fill the queue; the storehouse finds it full.
    { method: 'POST', path: '/v1/villages/1/build', body: { plot: 'f0' } },
    { method: 'POST', path: '/v1/villages/1/build', body: { plot: 'f3' } },
    { method: 'POST', path: '/v1/villages/1/build', body: { plot: 'f10' } },
    { method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c3', building: 'storehouse' } },
    { method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 5 } },
    { advance: 30 * MINUTE },
    { method: 'GET', path: '/v1/worlds/-1' },
    { method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c3', building: 'barracks' } },
    { method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 5 } },
    { method: 'POST', path: '/v1/villages/1/stance', body: { stance: 'defensive' } },
    { method: 'POST', path: '/v1/villages/1/outposts', body: { q: outpost.q, r: outpost.r } },
    { method: 'POST', path: '/v1/villages/1/outposts', body: { q: home.q, r: home.r } },
    { advance: 7 * MINUTE },
    { method: 'POST', path: '/v1/villages/1/build', body: { building: 'farm' } },
    { method: 'POST', path: '/v1/villages/1/rename', body: { name: 'Kitezh' } },
    { advance: 120 * MINUTE },
    { method: 'POST', path: '/v1/worlds/-1/onboarding/claim', body: { step: 'build' } },
    { method: 'POST', path: '/v1/worlds/-1/onboarding/claim', body: { step: 'scout' } },
    { method: 'POST', path: '/v1/villages/1/outposts', body: { q: outpost.q, r: outpost.r } },
    { method: 'POST', path: '/v1/villages/1/outposts/abandon', body: { q: outpost.q, r: outpost.r } },
    { advance: 60 * MINUTE },
    { method: 'POST', path: '/v1/worlds/-1/onboarding/claim', body: { step: 'outpost' } },
    { method: 'GET', path: '/v1/worlds/-1' },
    { method: 'POST', path: '/v1/villages/1/outposts/abandon', body: { q: outpost.q, r: outpost.r } },
    { method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 50 } },
    { advance: 45 * MINUTE + 17_000 },
    { method: 'GET', path: '/v1/worlds/-1' },
    // The walls, and a tower slot before and after they open it.
    { method: 'POST', path: '/v1/villages/1/build', body: { plot: 't0', building: 'archer_tower' } },
    { method: 'POST', path: '/v1/villages/1/build', body: { plot: 'w' } },
    { advance: 60 * MINUTE },
    { method: 'POST', path: '/v1/villages/1/build', body: { plot: 't0', building: 'archer_tower' } },
    // An outpost claimed again, then raised a level.
    { method: 'POST', path: '/v1/villages/1/outposts', body: { q: outpost.q, r: outpost.r } },
    { advance: 60 * MINUTE },
    { method: 'POST', path: '/v1/villages/1/build', body: { plot: `o${outpost.q},${outpost.r}` } },
    // Peaceful hours, then the world that reports them.
    { method: 'PUT', path: '/v1/worlds/-1/quiet', body: { start: 1320, end: 420, utcOffsetMinutes: 60 } },
    { method: 'GET', path: '/v1/worlds/-1' },
    { method: 'POST', path: '/v1/villages/1/market/trade', body: { give: 'wood', get: 'iron', amount: 100 } },
    { method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c3', building: 'market' } },
    { advance: 30 * MINUTE },
    { method: 'POST', path: '/v1/villages/1/market/trade', body: { give: 'wood', get: 'iron', amount: 100 } },
    { method: 'POST', path: '/v1/villages/1/market/trade', body: { give: 'grain', get: 'grain', amount: 10 } },
    { method: 'POST', path: '/v1/villages/1/market/trade', body: { give: 'stone', get: 'wood', amount: 1 } },
    { method: 'POST', path: '/v1/villages/1/market/sell', body: { item: 'perun_axe' } },
    { method: 'POST', path: '/v1/villages/1/demolish', body: { plot: 'c0' } },
    { method: 'POST', path: '/v1/villages/1/demolish', body: { plot: 'f0' } },
    { method: 'POST', path: '/v1/villages/1/demolish', body: { plot: 'c1' } },
    { method: 'POST', path: '/v1/villages/1/demolish', body: { plot: 'c3' } },
    { method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c3', building: 'forester' } },
    { method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c3', building: 'storehouse' } },
    { method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c1', building: 'storehouse' } },
    { advance: 30 * MINUTE },
    { method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c3', building: 'barracks' } },
    { method: 'GET', path: '/v1/worlds/-1' },
  ];
  for (const step of steps) await play(step);
});
