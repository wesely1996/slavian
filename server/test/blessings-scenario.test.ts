// The gods' blessings in a solo session (events.json blessings). The forge
// god's: spearmen forged to the last level of every line but one, then
// that one forged too: the blessing, and forging from then on at half the
// cost and time. The water god's: a river line of 14 dug edges ending at
// the village, and a 15th dug from its hex: the blessing, and an army
// marching along the river's banks at twice the pace. With both, every
// North horde to set out takes +10% hatred for good.
import { hex, hexKey, neighbors, type Hex } from '../src/sim/hex.js';
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Blessings', displayName: 'You', speed: 50, difficulty: 'baron' };

scenario('blessings-scenario.json', START, async ({ started, play }) => {
  const world = '/v1/worlds/-1';
  const home = hex(started.villages[0].q, started.villages[0].r);
  const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const land = (c: Hex) => ['plains', 'forest', 'hills', 'wooded_hills', 'swamp'].includes(terrain.get(hexKey(c)) ?? '');
  const common = (a: Hex, b: Hex) => neighbors(a).filter((n) => neighbors(b).some((m) => hexKey(m) === hexKey(n)));

  await play({ set: { amounts: { wood: 20000, stone: 20000, grain: 20000, iron: 20000 }, plots: { c2: { building: 'blacksmith', level: 10 } } } });

  // The forge god: every line of the spearman at its last level but attack.
  await play({ set: { smithing: { spearman: { attack: 2, defense: 3, health: 3, speed: 3, poison: 1 } } } });
  await play({ method: 'POST', path: '/v1/villages/1/smith', body: { unit: 'spearman', line: 'attack' } });
  await play({ advance: 30 * MINUTE });
  await play({ method: 'GET', path: world });
  // Blessed: the next forging costs half and takes half as long.
  await play({ method: 'POST', path: '/v1/villages/1/smith', body: { unit: 'archer', line: 'attack' } });

  // The water god: a strip of river edges, each meeting the next at a
  // corner, the last at the village; the 15th dug from the village's hex.
  const toward = neighbors(home).find((n) => land(n) && common(home, n).some(land))!;
  const strip: Hex[] = [home, toward, common(home, toward).find(land)!];
  while (strip.length < 17) {
    const [a, b, c] = strip.slice(-3) as [Hex, Hex, Hex];
    strip.push(common(b, c).find((n) => hexKey(n) !== hexKey(a))!);
  }
  const dug = strip.slice(1, 16).map((h, i) => ({ a: { q: h.q, r: h.r }, b: { q: strip[i + 2]!.q, r: strip[i + 2]!.r } })).slice(0, 14);
  await play({ set: { dugRivers: dug } });
  await play({ method: 'POST', path: '/v1/villages/1/terraform', body: { q: home.q, r: home.r, action: 'river', toward: { q: toward.q, r: toward.r } } });
  await play({ advance: 30 * MINUTE });
  await play({ method: 'GET', path: world });
  // Along the banks, twice the pace.
  await play({ set: { garrison: { spearman: 10 } } });
  const bank = strip[4]!;
  await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: { q: bank.q, r: bank.r }, units: { spearman: 5 } } });
  await play({ method: 'GET', path: world });
  await play({ method: 'GET', path: '/v1/worlds/-1/notifications' });
});
