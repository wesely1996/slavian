// Research, caravans, the vault and the hero's own commands in a solo
// session (docs/local-engine.md, part 5): a tech learned (and the ones
// refused), caravans to the Holy City vault and back, a vault upgrade
// refused, the hero renamed and refused what it can't do yet, and a
// caravan sent past the camp a beaten horde left by the road; caravans
// turned on their way out; a hero's quest called off.
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Roads', displayName: 'You', speed: 50, difficulty: 'normal' };
const load = (wood: number, stone = 0, grain = 0, iron = 0) => ({ wood, stone, grain, iron });

scenario('logistics-scenario.json', START, async ({ play }) => {
  const world = '/v1/worlds/-1';
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'academy' } });
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c3', building: 'caravan_yard' } });
  await play({ advance: 15 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/research', body: { tech: 'felling_axes' } });
  await play({ method: 'POST', path: '/v1/villages/1/research', body: { tech: 'two_field_rotation' } });
  await play({ method: 'POST', path: '/v1/villages/1/research', body: { tech: 'nonsense' } });
  await play({ method: 'POST', path: '/v1/villages/1/caravans', body: { destinationVillageId: null, load: load(100, 50) } });
  await play({ method: 'POST', path: '/v1/villages/1/caravans/fetch', body: { load: load(100) } });
  await play({ method: 'POST', path: '/v1/villages/1/caravans', body: { destinationVillageId: 1, load: load(10) } });
  await play({ method: `POST`, path: `${world}/vault/upgrade`, body: {} });
  await play({ method: 'POST', path: `${world}/hero/rename`, body: { name: 'Ilya' } });
  await play({ method: 'POST', path: `${world}/hero/skills`, body: { skill: 'battle_fury' } });
  await play({ method: 'POST', path: `${world}/hero/equip`, body: { item: 'mokosh_thread' } });
  await play({ method: 'POST', path: `${world}/hero/unequip`, body: { slot: 'amulet' } });
  await play({ method: 'POST', path: `${world}/hero/move`, body: { villageId: 1 } });
  await play({ method: 'POST', path: '/v1/villages/1/rebuild', body: {} });
  await play({ advance: 30 * MINUTE });
  await play({ method: 'GET', path: world });
  await play({ method: 'POST', path: '/v1/villages/1/research', body: { tech: 'stone_splitting' } });
  await play({ method: 'POST', path: '/v1/villages/1/caravans/fetch', body: { load: load(150, 50) } });
  await play({ advance: 10 * MINUTE });
  await play({ method: 'GET', path: world });
  // The first horde comes and goes; then a caravan takes the road past its camp.
  await play({ advance: 180 * MINUTE });
  await play({ method: 'GET', path: world });
  await play({ method: 'POST', path: '/v1/villages/1/caravans', body: { destinationVillageId: null, load: load(100, 0, 100) } });
  await play({ advance: 10 * MINUTE });
  await play({ method: 'GET', path: world });

  // Caravans turned on their way out: one to the vault can't be sent where
  // it already goes, nor home but by turning back; turned back, it brings
  // its goods home and can't be turned again. One fetching from the vault
  // can only turn back.
  const reroute = (id: number, body: object) => play({ method: 'POST', path: `/v1/caravans/${id}/reroute`, body });
  const out = (await play({ method: 'POST', path: '/v1/villages/1/caravans', body: { destinationVillageId: null, load: load(60, 0, 40) } })).body.caravan;
  await play({ advance: 20_000 });
  if (out) {
    await reroute(out.id, { villageId: null });
    await reroute(out.id, { villageId: 1 });
    await reroute(out.id, { home: true });
    await reroute(out.id, { home: true });
  }
  await play({ advance: 5 * MINUTE });
  const fetching = (await play({ method: 'POST', path: '/v1/villages/1/caravans/fetch', body: { load: load(50) } })).body.caravan;
  await play({ advance: 20_000 });
  if (fetching) {
    await reroute(fetching.id, { villageId: 1 });
    await reroute(fetching.id, { home: true });
  }
  await reroute(999, { home: true });
  await play({ advance: 10 * MINUTE });
  await play({ method: 'GET', path: world });

  // A quest called off on the way there: the hero turns for home, and can't
  // call it off twice; one with no quest can't either.
  await play({ method: 'POST', path: `${world}/hero/quest/cancel`, body: {} });
  const hero = (await play({ method: 'GET', path: world })).body.heroes[0];
  if (hero?.status === 'home' && hero.offers[0]) {
    await play({ method: 'POST', path: `${world}/hero/quest`, body: { offer: hero.offers[0].id } });
    await play({ advance: 20_000 });
    await play({ method: 'POST', path: `${world}/hero/quest/cancel`, body: {} });
    await play({ method: 'POST', path: `${world}/hero/quest/cancel`, body: {} });
    await play({ advance: 30_000 });
    await play({ method: 'GET', path: world });
    await play({ advance: 10 * MINUTE });
    await play({ method: 'GET', path: world });
  }
});
