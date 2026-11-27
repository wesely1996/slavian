// docs/state-machines.md draws every entity's lifecycle. It is reviewed at
// each release: its version line must match the app's version
// (client/project.godot), and every status value the code knows must appear
// in its entity's section.
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const root = new URL('../../', import.meta.url);
const read = (path: string) => readFileSync(new URL(path, root), 'utf8');
const doc = read('docs/state-machines.md');

// [section heading, source file, the line declaring the status values]
const MACHINES: [string, string, RegExp][] = [
  ['World', 'server/src/db/worlds.ts', /export type WorldStatus = ([^;]+);/],
  ['Wave (horde)', 'server/src/db/waves.ts', /export type WaveStatus = ([^;]+);/],
  ['Battle', 'server/src/db/battles.ts', /export type BattleStatus = ([^;]+);/],
  ['Army', 'server/src/db/armies.ts', /export type ArmyStatus = ([^;]+);/],
  ['Hero', 'server/src/sim/heroes.ts', /export type HeroStatus = ([^;]+);/],
  ['General', 'server/src/sim/generals.ts', /export type GeneralStatus = ([^;]+);/],
  ['Caravan', 'server/src/db/caravans.ts', /export type CaravanStatus = ([^;]+);/],
  ['Expedition (settlers)', 'server/src/db/expeditions.ts', /export type ExpeditionStatus = ([^;]+);/],
  ['Scout mission', 'server/src/db/scouting.ts', /export type MissionStatus = ([^;]+);/],
  ['Ruin search', 'server/src/db/ruinSearches.ts', /status: ('[^;]+);/],
  ['Road', 'server/src/db/roads.ts', /export type RoadStatus = ([^;]+);/],
  ['Edge wall', 'server/src/db/edgeWalls.ts', /export type EdgeWallStatus = ([^;]+);/],
  ['River crossing', 'server/src/db/rivers.ts', /export type Crossing = ([^;]+);/],
  ['Fort and supply point', 'server/src/db/forts.ts', /status: ('[^;]+);/],
  ['Camp', 'server/src/db/camps.ts', /status: ('[^;]+);/],
  ['Ancient site', 'server/src/db/sites.ts', /status: ('[^;]+);/],
  ['Shipyard and mountain city', 'server/src/db/shipyards.ts', /export type ShipyardStatus = ([^;]+);/],
  ['Research', 'server/src/db/research.ts', /status: ('[^;]+);/],
  ['Kalinov Bridge', 'server/src/sim/bridge.ts', /readonly status: ([^;]+);/],
  ['Enemy leader', 'server/src/db/leaders.ts', /status: ('[^;]+);/],
  ['Bounty', 'server/src/db/bounties.ts', /export type BountyStatus = ([^;]+);/],
];

function section(heading: string): string {
  const start = doc.indexOf(`\n## ${heading}\n`);
  if (start < 0) return '';
  const end = doc.indexOf('\n## ', start + 1);
  return doc.slice(start, end < 0 ? undefined : end);
}

describe('docs/state-machines.md', () => {
  it('is reviewed for the current version (bump its version line with config/version)', () => {
    const version = /^config\/version="([^"]+)"/m.exec(read('client/project.godot'))?.[1];
    const documented = /^Documented for version: (\S+)/m.exec(doc)?.[1];
    expect(version).toBeTruthy();
    expect(documented, 'docs/state-machines.md: review it and set "Documented for version"').toBe(version);
  });

  it.each(MACHINES)('draws every %s status', (heading, file, declared) => {
    const match = declared.exec(read(file));
    expect(match, `${file}: status declaration not found`).toBeTruthy();
    const statuses = [...match![1]!.matchAll(/'([a-z_]+)'/g)].map((m) => m[1]!);
    expect(statuses.length).toBeGreaterThan(1);
    const text = section(heading);
    expect(text, `no "## ${heading}" section`).not.toBe('');
    const missing = statuses.filter((s) => !new RegExp(`\\b${s}\\b`).test(text));
    expect(missing, `${heading}: statuses missing from its diagram`).toEqual([]);
  });
});
