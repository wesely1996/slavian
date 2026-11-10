// Strikes on gathering hordes in a solo session: refused for a horde that
// doesn't exist; an army strikes one horde long before it sets out (only a
// share of it has gathered) and another just before it does; a strike on a
// horde already on the march is refused. The dead are gone from the horde,
// and the front's next horde hates the more.
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Strike', displayName: 'You', speed: 50, difficulty: 'normal' };
// A game hour at speed 50.
const HOUR = (60 * MINUTE) / 50;

scenario('strike-scenario.json', START, async ({ play }) => {
  const world = '/v1/worlds/-1';
  const strike = (body: object) => play({ method: 'POST', path: '/v1/villages/1/strike', body });
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'barracks' } });
  await play({ advance: 20 * MINUTE });
  for (let i = 0; i < 3; i++) {
    await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 8 } });
    await play({ advance: 30 * MINUTE });
  }
  type WaveView = { id: number; status: string; bandOf: number | null; spawnAt: string; front: string };
  const waves = async () => ((await play({ method: 'GET', path: world })).body.waves as WaveView[]).filter((w) => w.bandOf === null);
  const garrison = (await play({ method: 'GET', path: world })).body.villages[0].garrison.spearman ?? 0;
  const half = Math.max(1, Math.floor(garrison / 2));
  const scheduled = (await waves()).filter((w) => w.status === 'scheduled').sort((a, b) => a.spawnAt.localeCompare(b.spawnAt) || a.id - b.id);
  await strike({ waveId: 999, units: { spearman: 2 } });
  // The last horde announced: long before it sets out.
  await strike({ waveId: scheduled[scheduled.length - 1]!.id, units: { spearman: half }, stance: 'offensive' });
  // The first: just before it sets out.
  await strike({ waveId: scheduled[0]!.id, units: { spearman: half } });
  for (let i = 0; i < 4; i++) {
    await play({ advance: 2 * HOUR });
    await play({ method: 'GET', path: world });
  }
  await play({ advance: 30 * MINUTE });
  // The first horde has set out by now: too late to strike it in its camp.
  await strike({ waveId: scheduled[0]!.id, units: { spearman: 1 } });
  await play({ advance: 6 * HOUR });
  await play({ method: 'GET', path: world });
});
