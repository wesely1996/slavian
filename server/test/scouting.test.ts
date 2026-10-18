import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { hex } from '../src/sim/hex.js';
import { generateMap } from '../src/sim/mapgen.js';
import { scoutReport, scoutTarget, scoutTravelMs, survivorsOf } from '../src/sim/scouting.js';
import { completeBuild, loseAway, newVillage, queueBuild, queueTraining, returnHome, sendAway } from '../src/sim/village.js';
import { RuleError } from '../src/errors.js';

const data = loadGameData();
const composition = { grey_wolf: 14, leshy_thrall: 7, cave_bear: 4 };
const total = 25;
const report = (survivors: number, missionId = 1, dispersed = false) =>
  scoutReport(data, { front: 'north', composition, stance: 'offensive', sent: 8, survivors, dispersed, seed: 77, missionId });

describe('scout survival', () => {
  it('is deterministic per mission and roughly matches the front survival chance', () => {
    expect(survivorsOf(data, 'north', 10, 5, 3)).toBe(survivorsOf(data, 'north', 10, 5, 3));
    let survived = 0;
    for (let mission = 0; mission < 400; mission++) survived += survivorsOf(data, 'north', 10, 5, mission);
    expect(survived / 4000).toBeGreaterThan(0.7);
    expect(survived / 4000).toBeLessThan(0.8);
  });
});

describe('scout reports', () => {
  it('reports nothing when no scout survives', () => {
    expect(report(0)).toMatchObject({ tier: 'none', size: null, units: [] });
  });

  it('rough: a size range and only the most numerous unit, without counts', () => {
    const r = report(2);
    expect(r.tier).toBe('rough');
    expect(r.units).toEqual([{ unit: 'grey_wolf', name: 'Grey Wolf', min: null, max: null }]);
    expect(r.size!.min).toBeLessThanOrEqual(total);
    expect(r.size!.max).toBeGreaterThanOrEqual(total);
  });

  it('detailed: every unit with a range around its true count', () => {
    const r = report(4);
    expect(r.tier).toBe('detailed');
    expect(r.units.map((u) => u.unit)).toEqual(['grey_wolf', 'leshy_thrall', 'cave_bear']);
    for (const u of r.units) {
      const actual = composition[u.unit as keyof typeof composition];
      expect(u.min!).toBeLessThanOrEqual(actual);
      expect(u.max!).toBeGreaterThanOrEqual(actual);
    }
  });

  it('reveals the stance only in detailed and exact reports', () => {
    expect(report(2).stance).toBeNull();
    expect(report(4).stance).toBe('offensive');
    expect(report(6).stance).toBe('offensive');
  });

  it('exact: the true roster', () => {
    const r = report(6);
    expect(r.tier).toBe('exact');
    expect(r.size).toEqual({ min: total, max: total });
    expect(r.units.map((u) => [u.unit, u.min, u.max])).toEqual([
      ['grey_wolf', 14, 14],
      ['leshy_thrall', 7, 7],
      ['cave_bear', 4, 4],
    ]);
  });

  it('ranges always contain the truth, whatever the noise', () => {
    for (let mission = 0; mission < 200; mission++) {
      const r = report(3, mission);
      expect(r.size!.min).toBeLessThanOrEqual(total);
      expect(r.size!.max).toBeGreaterThanOrEqual(total);
    }
  });

  it('a scattered horde leaves nothing to report', () => {
    expect(report(8, 1, true)).toMatchObject({ tier: 'none', dispersed: true });
  });
});

describe('scout targets and travel', () => {
  const map = generateMap(data, 99, 2);
  const home = map.startSites[0]!;

  it('finds a scheduled wave in its spawn zone, a marching one on its path', () => {
    const gathering = scoutTarget(data, map.terrain, { front: 'north', status: 'scheduled', spawnAt: new Date(0), path: null }, home, new Date(0));
    expect(['dark_forest', 'ice']).toContain(map.terrain.get(`${gathering.q},${gathering.r}`));
    const path = [{ q: 0, r: -9, atMs: 0 }, { q: 0, r: -8, atMs: 1000 }, { q: 0, r: -7, atMs: 2000 }];
    const marching = scoutTarget(data, map.terrain, { front: 'north', status: 'marching', spawnAt: new Date(0), path }, home, new Date(1500));
    expect(marching).toEqual(hex(0, -8));
  });

  it('travels faster in faster worlds', () => {
    const target = hex(0, -6);
    expect(scoutTravelMs(data, map.terrain, home, target, 10)).toBe(Math.round(scoutTravelMs(data, map.terrain, home, target, 1) / 10));
  });
});

describe('units away', () => {
  const T0 = new Date('2026-04-01T00:00:00Z');
  function withScouts(count: number) {
    const fresh = newVillage(data, T0, 1);
    let state = { ...fresh, ledger: { ...fresh.ledger, amounts: { wood: 9e4, stone: 9e4, grain: 9e4, iron: 9e4 }, capacity: { wood: 9e9, stone: 9e9, grain: 9e9, iron: 9e9 } } };
    const built = queueBuild(data, state, 'scout_lodge', T0, 1);
    state = completeBuild(data, built.state, built.queued.plot, 1, built.queued.completesAt, 1);
    const trained = queueTraining(data, state, 'scout', count, built.queued.completesAt, 1);
    return { state: trained.state, ready: new Date(built.queued.completesAt.getTime() + count * trained.batch.perUnitMs) };
  }

  it('sends only units that are home, counting finished training', () => {
    const { state, ready } = withScouts(4);
    expect(() => sendAway(state, 'scout', 1, new Date(ready.getTime() - 1e9))).toThrow(RuleError);
    const away = sendAway(state, 'scout', 3, ready);
    expect(away.garrison.scout).toBe(1);
    expect(away.away.scout).toBe(3);
    expect(() => sendAway(away, 'scout', 2, ready)).toThrow(/Only 1 scout/);
  });

  it('keeps feeding units away, stops for the dead, and brings survivors home', () => {
    const { state, ready } = withScouts(4);
    const away = sendAway(state, 'scout', 4, ready);
    expect(away.ledger.ratesPerHour.grain).toBe(state.ledger.ratesPerHour.grain);
    const lost = loseAway(data, away, 'scout', 1, ready, 1);
    expect(lost.ledger.ratesPerHour.grain).toBe(state.ledger.ratesPerHour.grain + 1);
    const back = returnHome(lost, 'scout', 3);
    expect(back.garrison.scout).toBe(3);
    expect(back.away.scout).toBe(0);
  });
});
