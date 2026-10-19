import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { validateArmy } from '../src/sim/armies.js';
import { hex, hexDistance, hexKey } from '../src/sim/hex.js';
import { generateMap } from '../src/sim/mapgen.js';
import { researchProblem } from '../src/sim/research.js';
import { distanceShare, loreBonuses, placeSites, rollFind } from '../src/sim/sites.js';

const data = loadGameData();

describe('ancient sites', () => {
  const map = generateMap(data, 77, 3);
  const sites = placeSites(data, { terrain: map.terrain, radius: map.radius, startSites: map.startSites, seed: 77, players: 3 });

  it('lie apart, away from start sites, on ground their kind fits', () => {
    const p = data.sites.placement;
    expect(sites.length).toBeGreaterThanOrEqual(p.min);
    expect(sites.length).toBeLessThanOrEqual(p.perPlayer * 3);
    for (const [i, site] of sites.entries()) {
      const cell = hex(site.q, site.r);
      expect(data.sites.kinds[site.kind]!.terrain).toContain(map.terrain.get(hexKey(cell)));
      expect(map.startSites.every((s) => hexDistance(s, cell) >= p.keepAway)).toBe(true);
      for (const other of sites.slice(i + 1)) expect(hexDistance(cell, hex(other.q, other.r))).toBeGreaterThanOrEqual(p.spacing);
    }
    // Mostly in the borderlands.
    const border = sites.filter((s) => hexDistance(hex(s.q, s.r), hex(0, 0)) >= map.radius - p.borderBand);
    expect(border.length).toBeGreaterThan(sites.length / 2);
    expect(sites.some((s) => Object.keys(s.guardians).length > 0)).toBe(true);
    expect(placeSites(data, { terrain: map.terrain, radius: map.radius, startSites: map.startSites, seed: 77, players: 3 })).toEqual(sites);
  });

  it('give up a find, never a scroll or gear the group already has', () => {
    const base = { kind: 'stone_idol', seed: 5, siteId: 1, distance: 1, foundScrolls: new Set<string>(), ownedGear: new Set<string>() };
    expect(rollFind(data, base)).toEqual(rollFind(data, base));
    const allScrolls = new Set(Object.keys(data.lore.scrolls));
    const allGear = new Set(Object.keys(data.heroes.items));
    for (let id = 0; id < 40; id++) {
      const find = rollFind(data, { ...base, siteId: id, foundScrolls: allScrolls, ownedGear: allGear });
      expect(['resources', 'ember']).toContain(find.type);
      if (find.type === 'resources') expect(find.resources.wood).toBe(data.sites.loot.wood * 2);
    }
    const kinds = new Set(Array.from({ length: 60 }, (_, id) => rollFind(data, { ...base, siteId: id }).type));
    expect(kinds).toEqual(new Set(['resources', 'gear', 'scroll', 'ember']));
    expect(distanceShare(hex(0, 0), 10)).toBe(0);
  });

  it('let scouts explore, and scrolls boost the group or unlock rare techs', () => {
    expect(validateArmy(data, { scout: 3 }, 'explore')).toEqual({ scout: 3 });
    expect(() => validateArmy(data, { scout: 3 }, 'clear')).toThrow(/don't march/);
    expect(loreBonuses(data, ['perun_oath', 'dazhbog_hymn'])).toEqual({ 'attack.all': 0.05, 'defense.all': 0.05 });
    const input = { academyLevel: 5, done: new Set<string>(), researching: false };
    expect(researchProblem(data, 'wind_riders', input)).toMatch(/Winds of Stribog/);
    expect(researchProblem(data, 'wind_riders', { ...input, scrolls: new Set(['stribog_winds']) })).toBeNull();
  });
});
