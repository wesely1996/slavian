import { describe, expect, it } from 'vitest';
import { hex } from '../src/sim/hex.js';
import { detour, hordeDetour } from '../src/scheduler/detours.js';

// A road east along r = 0: a hex every 10 s.
const road = [0, 1, 2, 3, 4].map((q) => ({ q, r: 0, atMs: q * 10_000 }));
const around = (from: { q: number; r: number }) => [
  { q: from.q, r: from.r, atMs: 0 },
  { q: from.q + 1, r: -1, atMs: 12_000 },
  { q: 4, r: 0, atMs: 30_000 },
];

describe('going round a fire', () => {
  it('an army headed straight into it walks back and goes round', () => {
    // 4 s into the step from (1,0) to the burning (2,0): 4 s back to (1,0).
    expect(detour(road, 14_000, hex(2, 0), around)).toEqual([
      { q: 0, r: 0, atMs: 0 },
      { q: 1, r: 0, atMs: 10_000 },
      { q: 1, r: 0, atMs: 18_000 },
      { q: 2, r: -1, atMs: 30_000 },
      { q: 4, r: 0, atMs: 48_000 },
    ]);
    expect(detour(road, 14_000, hex(2, 0), () => null)).toBeNull();
  });

  it('a horde never turns back: it swerves on, or waits at the edge until the fire is out', () => {
    expect(hordeDetour(road, 14_000, hex(2, 0), 60_000, around)).toEqual([
      { q: 0, r: 0, atMs: 0 },
      { q: 1, r: 0, atMs: 14_000 },
      { q: 2, r: -1, atMs: 26_000 },
      { q: 4, r: 0, atMs: 44_000 },
    ]);
    // No way round: from the burning hex on, it comes 40 s later (out at 60 s).
    expect(hordeDetour(road, 14_000, hex(2, 0), 60_000, () => null)).toEqual([
      { q: 0, r: 0, atMs: 0 },
      { q: 1, r: 0, atMs: 10_000 },
      { q: 2, r: 0, atMs: 60_000 },
      { q: 3, r: 0, atMs: 70_000 },
      { q: 4, r: 0, atMs: 80_000 },
    ]);
    // A fire further on: round it from the hex it is heading into.
    expect(hordeDetour(road, 4_000, hex(3, 0), 60_000, around)[1]).toEqual({ q: 1, r: 0, atMs: 10_000 });
  });
});
