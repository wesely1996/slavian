// Raids in a solo session: refused for a side no enemy comes from and for a
// depth past the deepest; then an army raids the North one field deep
// (and the North's stronghold after it) and another the South two fields
// deep, each fighting its stages beyond the map's edge and coming home with
// what it carries; one is called home in the middle of its raid.
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Raids', displayName: 'You', speed: 50, difficulty: 'normal' };
// A game hour at speed 50.
const HOUR = (60 * MINUTE) / 50;

scenario('raids-scenario.json', START, async ({ play }) => {
  const world = '/v1/worlds/-1';
  const raid = (body: object) => play({ method: 'POST', path: '/v1/villages/1/raids', body });
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'barracks' } });
  await play({ advance: 20 * MINUTE });
  // A few days of training: a big band of spearmen.
  for (let i = 0; i < 3; i++) {
    await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 8 } });
    await play({ advance: 40 * MINUTE });
  }
  const garrison = (await play({ method: 'GET', path: world })).body.villages[0].garrison.spearman ?? 0;

  await raid({ front: 'east', depth: 1, units: { spearman: 2 } });
  await raid({ front: 'north', depth: 9, units: { spearman: 2 } });
  await raid({ front: 'north', depth: 1, units: { spearman: Math.max(1, garrison - 6) }, stance: 'offensive' });
  await raid({ front: 'south', depth: 2, units: { spearman: 2 } });
  await raid({ front: 'south', depth: 1, units: { spearman: 1 } });
  await play({ method: 'GET', path: world });
  // On the march, at the edge, and through the stages.
  for (let i = 0; i < 6; i++) {
    await play({ advance: 2 * HOUR });
    const view = (await play({ method: 'GET', path: world })).body;
    // The smallest raid is called home once it stands beyond the edge.
    const small = (view.armies as { id: number; status: string; orders: string; units: Record<string, number> }[]).find((a) => a.orders === 'raid' && a.units.spearman === 1);
    if (i === 1 && small && small.status === 'stationed') await play({ method: 'POST', path: `/v1/armies/${small.id}/recall`, body: {} });
  }
  await play({ advance: 12 * HOUR });
  await play({ method: 'GET', path: world });
});
