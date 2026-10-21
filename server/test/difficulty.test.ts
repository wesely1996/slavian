import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import type { World } from '../src/db/worlds.js';
import { holdForQuiet } from '../src/scheduler/waves.js';
import { afterQuiet, campsPerWave, waveFactor } from '../src/sim/difficulty.js';
import { decideRaze } from '../src/sim/horde.js';

const data = loadGameData();
const quiet = { start: 22 * 60, end: 7 * 60, utcOffsetMinutes: 120 };

describe('difficulty', () => {
  const base = { players: 2, villages: 2, armyAttack: 0, waveIndex: 3 };
  const normal = data.difficulty.presets.normal.waveScale;

  it('scales waves by preset, between floor and cap', () => {
    expect(waveFactor(data, 'normal', base)).toBeCloseTo(normal);
    expect(waveFactor(data, 'story', base)).toBe(0.7);
    expect(waveFactor(data, 'nightmare', base)).toBe(1.5);
    // A huge group hits the cap; nothing goes below the floor.
    expect(waveFactor(data, 'normal', { ...base, villages: 40 })).toBe(data.difficulty.presets.normal.maxFactor);
    expect(waveFactor(data, 'story', { ...base, players: 0 })).toBeGreaterThanOrEqual(data.difficulty.presets.story.floor);
  });

  it('grows waves with extra villages and an army above the curve', () => {
    expect(waveFactor(data, 'normal', { ...base, villages: 4 })).toBeCloseTo(1.5 * normal);
    const expected = 2 * data.difficulty.power.attackPerPlayer * (1 + data.difficulty.power.growthPerWave * 3);
    expect(waveFactor(data, 'normal', { ...base, armyAttack: expected })).toBeCloseTo(normal);
    expect(waveFactor(data, 'normal', { ...base, armyAttack: expected * 2 })).toBeCloseTo(1.5 * normal);
  });

  it('sets how many camps rise and how hordes decide', () => {
    expect(campsPerWave(data, 'normal', 0.99)).toBe(1);
    expect(campsPerWave(data, 'story', 0.2)).toBe(1);
    expect(campsPerWave(data, 'story', 0.8)).toBe(0);
    expect(campsPerWave(data, 'nightmare', 0.5)).toBe(2);
    const raze = { front: 'south' as const, waveIndex: 1, hordeNow: 60, hordeInitial: 80, helpNearby: 10, rampageLeftMs: 1e9, worldSpeed: 1 };
    expect(decideRaze(data, raze).choice).toBe('raid');
    expect(decideRaze(data, { ...raze, graceWaves: 0 }).choice).toBe('raze');
    expect(decideRaze(data, { ...raze, waveIndex: 5, thresholdOffset: 5 }).choice).toBe('raid');
  });
});

describe('quiet hours', () => {
  it('hold arrivals until the window ends, in the group\'s time', () => {
    // 21:30 UTC is 23:30 local (+2): inside 22:00–07:00, so 07:00 local = 05:00 UTC.
    expect(afterQuiet(quiet, new Date('2026-05-01T21:30:00Z')).toISOString()).toBe('2026-05-02T05:00:00.000Z');
    expect(afterQuiet(quiet, new Date('2026-05-02T03:15:00Z')).toISOString()).toBe('2026-05-02T05:00:00.000Z');
    const day = new Date('2026-05-02T10:00:00Z');
    expect(afterQuiet(quiet, day)).toBe(day);
    expect(afterQuiet(null, new Date('2026-05-01T21:30:00Z')).toISOString()).toBe('2026-05-01T21:30:00.000Z');
  });

  it('make the horde wait outside before its last step', () => {
    const world = { quietStart: quiet.start, quietEnd: quiet.end, quietUtcOffset: quiet.utcOffsetMinutes } as World;
    const spawnAt = new Date('2026-05-01T20:00:00Z');
    const march = { path: [{ q: 0, r: 0, atMs: 0 }, { q: 1, r: 0, atMs: 3_600_000 }, { q: 2, r: 0, atMs: 7_200_000 }], arrivesAt: new Date('2026-05-01T22:00:00Z') };
    const held = holdForQuiet(world, spawnAt, march);
    expect(held.arrivesAt.toISOString()).toBe('2026-05-02T05:00:00.000Z');
    expect(held.path.map((s) => s.atMs)).toEqual([0, 3_600_000, 9 * 3_600_000]);
    const free = { ...world, quietStart: null } as World;
    expect(holdForQuiet(free, spawnAt, march)).toBe(march);
  });
});
