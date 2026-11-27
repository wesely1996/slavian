// Seasons in a solo session (data/seasons.json): one game day each. The
// village's grain doubles in summer and stops in winter, every turn is told
// in the inbox, and the hordes' fronts are drawn for the season they set
// out in.
import { MINUTE, scenario, scheduler } from './scenario.js';

const START = { seed: 7373, at: '2026-06-01T08:00:00.000Z', name: 'Seasons', displayName: 'You', speed: 100, difficulty: 'baron' };

scenario('seasons-scenario.json', START, async ({ play }) => {
  const day = (scheduler.data.seasons.dayHours * 60 * MINUTE) / START.speed;
  await play({ method: 'GET', path: '/v1/worlds/-1' });
  // Through a year: spring, summer, autumn, winter, and spring again.
  for (let i = 0; i < 5; i++) {
    await play({ advance: day / 2 });
    await play({ method: 'GET', path: '/v1/worlds/-1' });
    await play({ advance: day / 2 });
    await play({ method: 'GET', path: '/v1/worlds/-1/notifications' });
  }
});
