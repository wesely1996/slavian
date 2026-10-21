// Writes the shared fixtures the client's local engine is checked against
// (PLAN.md M5 step 24), and the game data the app bundles for it: the
// server's rules are the reference, the GDScript port must give the same
// results. `npm run fixtures` after changing a rule or anything in data/;
// test/fixtures.test.ts fails while either is out of date.
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createNoise2D } from 'simplex-noise';
import { loadGameData, type GameData } from './data/index.js';
import { hexKey, spiral, hex } from './sim/hex.js';
import { generateMap } from './sim/mapgen.js';
import { createRng } from './sim/rng.js';

export const MAPGEN_FIXTURE = fileURLToPath(new URL('../../data/fixtures/mapgen-vectors.json', import.meta.url));
// The game data as the server reads it (defaults filled in), bundled into the
// app for the local engine.
export const CLIENT_DATA = fileURLToPath(new URL('../../client/data/game.json', import.meta.url));

export function clientData(data: GameData): string {
  return JSON.stringify(data) + '\n';
}

export function mapgenVectors(data: GameData) {
  const rng = [1, 42, 0x7fffffff, 0xdeadbeef].map((seed) => {
    const next = createRng(seed);
    // As 32-bit integers (value x 2^32): exact through any JSON parser.
    return { seed, values: Array.from({ length: 6 }, () => next() * 4294967296) };
  });
  const noise = [3, 2026].map((seed) => {
    const noise2D = createNoise2D(createRng(seed));
    const points = [[0, 0], [0.37, -1.2], [5.5, 2.25], [-13.1, 7.9], [100.03, -42.7]].map(([x, y]) => [x!, y!, noise2D(x!, y!)]);
    return { seed, points };
  });
  const maps = [
    [12345, 1],
    [12345, 2],
    [777, 3],
    [90210, 4],
    [31337, 6],
  ].map(([seed, players]) => {
    const map = generateMap(data, seed!, players!);
    return {
      seed,
      players,
      // The seed that made a playable map (generateMap retries).
      madeWith: map.seed,
      radius: map.radius,
      activeFronts: map.activeFronts,
      startSites: map.startSites.map((s) => [s.q, s.r]),
      // Terrain in spiral order from the Holy City.
      terrain: spiral(hex(0, 0), map.radius).map((cell) => map.terrain.get(hexKey(cell))).join(','),
      rivers: map.rivers.map((e) => [e.a.q, e.a.r, e.b.q, e.b.r, e.bridge ? 1 : 0, e.size]),
    };
  });
  return { _comment: 'Written by `npm run fixtures` (server/src/fixtures.ts) from the server rules; the client local engine must match.', rng, noise, maps };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const data = loadGameData();
  writeFileSync(MAPGEN_FIXTURE, JSON.stringify(mapgenVectors(data), null, 1) + '\n');
  writeFileSync(CLIENT_DATA, clientData(data));
  console.log(`Wrote ${MAPGEN_FIXTURE} and ${CLIENT_DATA}`);
}
