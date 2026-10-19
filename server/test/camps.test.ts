import { describe, expect, it } from 'vitest';
import { loadGameData, type TerrainId } from '../src/data/index.js';
import { playerStats, total } from '../src/sim/battle.js';
import { ambush, assault, campLoot, campSize, feed, grow, passesCamp, spawnSites } from '../src/sim/camps.js';
import { hex, hexDistance, hexKey, spiral } from '../src/sim/hex.js';

const data = loadGameData();

describe('camps', () => {
  it('grow with each wave, and slowly over time up to a limit', () => {
    expect(campSize(data, 0)).toBe(data.camps.spawn.baseUnits);
    expect(campSize(data, 6)).toBeGreaterThan(campSize(data, 0));
    expect(total(grow(data, { zealot: 20, crossbowman: 10 }))).toBe(33);
    expect(total(grow(data, { zealot: 1 }))).toBe(2);
    expect(grow(data, { zealot: data.camps.growth.maxUnits })).toEqual({ zealot: data.camps.growth.maxUnits });
  });

  it('send part of themselves with the next wave', () => {
    expect(feed(data, { zealot: 10, crossbowman: 3 })).toEqual({ sent: { zealot: 5, crossbowman: 1 }, kept: { zealot: 5, crossbowman: 2 } });
  });

  it('spawn near the road, away from villages and each other', () => {
    const terrain = new Map(spiral(hex(0, 0), 8).map((c) => [hexKey(c), 'plains' as TerrainId]));
    const path = [0, 1, 2, 3, 4, 5, 6].map((i) => ({ q: i, r: -i, atMs: i }));
    const sites = spawnSites(data, { terrain, path, villages: [hex(6, -6)], taken: new Set([hexKey(hex(2, -2))]), rng: () => 0.5, count: 3 });
    expect(sites).toHaveLength(3);
    for (const site of sites) {
      expect(path.some((s) => hexDistance(hex(s.q, s.r), site) <= data.camps.spawn.nearRoad)).toBe(true);
      expect(hexDistance(site, hex(6, -6))).toBeGreaterThanOrEqual(data.camps.spawn.minVillageDistance);
      expect(hexKey(site)).not.toBe(hexKey(hex(2, -2)));
    }
    expect(hexDistance(sites[0]!, sites[1]!)).toBeGreaterThan(1);
  });

  it('fall to a strong army and hold against a weak one', () => {
    const stats = playerStats(data, {}, false);
    const strong = assault(data, { army: { spearman: 80, archer: 40 }, armyStats: stats, armyStance: 'offensive', camp: { zealot: 8, crossbowman: 4 }, front: 'south', seed: 1, id: 1 });
    expect(strong.cleared).toBe(true);
    expect(total(strong.armyNow)).toBeGreaterThan(80);
    const weak = assault(data, { army: { spearman: 3 }, armyStats: stats, armyStance: 'balanced', camp: { zealot: 30, crossbowman: 10 }, front: 'south', seed: 1, id: 1 });
    expect(weak.cleared).toBe(false);
    expect(weak.rounds.at(-1)!.attackerLeft).toBe(total(weak.armyNow));
    expect(campLoot(data, { zealot: 10 })).toEqual({ wood: 150, stone: 150, grain: 150, iron: 80 });
  });

  it('ambush caravans unless an escort can beat them off', () => {
    const stats = playerStats(data, {}, false);
    const cargo = { wood: 300, stone: 101, grain: 0, iron: 0 };
    const robbed = ambush(data, { escort: {}, escortStats: stats, camp: { zealot: 10 }, front: 'south', cargo });
    expect(robbed).toEqual({ beatenOff: false, lost: { wood: 150, stone: 50, grain: 0, iron: 0 }, escortLosses: {} });
    const thin = ambush(data, { escort: { spearman: 2 }, escortStats: stats, camp: { zealot: 10 }, front: 'south', cargo });
    expect(thin.beatenOff).toBe(false);
    expect(thin.escortLosses).toEqual({ spearman: 1 });
    expect(ambush(data, { escort: { archer: 10 }, escortStats: stats, camp: { zealot: 10 }, front: 'south', cargo }).beatenOff).toBe(true);
    expect(passesCamp(data, [{ q: 0, r: 0, atMs: 0 }, { q: 1, r: 0, atMs: 5 }], hex(2, 0))).toEqual({ q: 1, r: 0, atMs: 5 });
    expect(passesCamp(data, [{ q: 0, r: 0, atMs: 0 }], hex(3, 0))).toBeNull();
  });
});
