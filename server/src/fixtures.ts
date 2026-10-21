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
import { localize, NOTICE_TABLES } from './i18n.js';
import { generateMap } from './sim/mapgen.js';
import { digestSummary, SERBIAN_LABELS } from './sim/notifications.js';
import { createRng } from './sim/rng.js';

export const NOTICE_FIXTURE = fileURLToPath(new URL('../../data/fixtures/notice-vectors.json', import.meta.url));

// Notices as the server renders them, in English and Serbian: templates
// from the notice table and the client's catalog, values translated too.
export function noticeVectors() {
  const samples: [string, Record<string, string | number>][] = [
    ['A horde is coming to {village}', { village: 'Kitezh' }],
    ['The {threat} {front} horde arrives in about {hours} hours. Check the garrison and its stance.', { threat: 'low', front: 'north', hours: 3 }],
    ['{village} was raided', { village: 'Vruchiy' }],
    ['{tech} researched', { tech: 'Felling Axes' }],
    ['{enemy} against {defenders}, with {ground}.', { enemy: 12, defenders: 7.5, ground: 'an ambush, a choke point' }],
    ['Done: {step}', { step: 'Raise a building' }],
    ['Not a notice at all, {name}', { name: 'Ilya' }],
  ];
  const localized = ['en', 'sr', 'sr_Latn'].flatMap((language) =>
    samples.map(([template, vars]) => ({ language, template, vars, text: localize(language, template, vars) })),
  );
  const kinds = ['build_done', 'build_done', 'battle_result', 'hero', 'outpost_raided', 'build_done'];
  const digests = ['en', 'sr'].map((language) => ({ language, kinds, text: digestSummary(kinds, language) }));
  return { _comment: 'Written by `npm run fixtures` (server/src/fixtures.ts): notices as the server renders them; the local engine must match.', localized, digests };
}

export const MAPGEN_FIXTURE = fileURLToPath(new URL('../../data/fixtures/mapgen-vectors.json', import.meta.url));
// The game data as the server reads it (defaults filled in), bundled into the
// app for the local engine.
export const CLIENT_DATA = fileURLToPath(new URL('../../client/data/game.json', import.meta.url));

export function clientData(data: GameData): string {
  return JSON.stringify(data) + '\n';
}

// The notice templates' translations (i18n.ts) and the digest's labels
// (sim/notifications.ts), for the local engine's inbox.
export const CLIENT_NOTICES = fileURLToPath(new URL('../../client/data/notices.json', import.meta.url));

export function clientNotices(): string {
  return JSON.stringify({ tables: NOTICE_TABLES, digestLabels: { sr: SERBIAN_LABELS } }, null, 1) + '\n';
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
  writeFileSync(CLIENT_NOTICES, clientNotices());
  writeFileSync(NOTICE_FIXTURE, JSON.stringify(noticeVectors(), null, 1) + '\n');
  console.log(`Wrote ${MAPGEN_FIXTURE}, ${NOTICE_FIXTURE}, ${CLIENT_DATA} and ${CLIENT_NOTICES}`);
}
