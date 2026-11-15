// Svarog's Embers spent in a solo session: a Shrine needs one for every
// level (refused without, given back when a level is called off), its god
// is picked once it stands (and only once) and blesses the player more with
// every level, and turning to another god takes an Ember; the mightiest
// techs take Embers too.
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Shrine', displayName: 'You', speed: 50, difficulty: 'normal' };

scenario('shrine-scenario.json', START, async ({ play }) => {
  const world = '/v1/worlds/-1';
  const village = '/v1/villages/1';
  const full = { wood: 1000, stone: 1000, grain: 1000, iron: 1000 };
  const build = (body: object) => play({ method: 'POST', path: `${village}/build`, body });
  const deity = (name: string) => play({ method: 'POST', path: `${village}/deity`, body: { deity: name } });

  // A Hall of level 3 stands; the group has no Ember: no Shrine.
  await play({ set: { plots: { c0: { building: 'elder_hall', level: 3 } }, amounts: full, embers: 0 } });
  await build({ plot: 'c2', building: 'shrine' });
  // With Embers it rises, one spent; no god before it stands.
  await play({ set: { embers: 3 } });
  await build({ plot: 'c2', building: 'shrine' });
  await deity('perun');
  // Its second level queued takes another Ember; called off, it comes back.
  await play({ set: { amounts: full } });
  await build({ plot: 'c2' });
  await play({ method: 'POST', path: `${village}/build/cancel`, body: { plot: 'c2', targetLevel: 2 } });
  await play({ advance: 20 * MINUTE });
  // Its god: none such, then Dazhbog (not twice); another takes an Ember.
  await deity('zeus');
  await deity('dazhbog');
  await deity('dazhbog');
  await play({ set: { embers: 0 } });
  await deity('perun');
  await play({ set: { embers: 2 } });
  await play({ method: 'GET', path: world });
  // A second level: the blessing doubles.
  await play({ set: { amounts: full } });
  await build({ plot: 'c2' });
  await play({ advance: 20 * MINUTE });
  await play({ method: 'GET', path: world });
  // Turned to Perun for the last Ember: Dazhbog's blessing goes, Perun's comes.
  await deity('perun');
  await play({ method: 'GET', path: world });

  // An Ember tech: refused while the group has too few, started with enough.
  await play({ set: { plots: { c3: { building: 'academy', level: 5 } }, known: ['frontier_tithes'], researchPoints: 5000, embers: 1 } });
  await play({ method: 'POST', path: `${village}/research`, body: { tech: 'rod_abundance' } });
  await play({ set: { embers: 2 } });
  await play({ method: 'POST', path: `${village}/research`, body: { tech: 'rod_abundance' } });
  await play({ method: 'GET', path: world });
});
