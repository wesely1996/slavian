import { describe, expect, it } from 'vitest';
import { hex } from '../src/sim/hex.js';
import { withoutHalts } from '../src/sim/logistics.js';
import { bestWay, detour, waitOut } from '../src/scheduler/detours.js';

// A road east along r = 0: a hex every 10 s. Ways round: a quick one and a
// slow one.
const road = [0, 1, 2, 3, 4].map((q) => ({ q, r: 0, atMs: q * 10_000 }));
const around = (from: { q: number; r: number }) => [{ q: from.q, r: from.r, atMs: 0 }, { q: from.q + 1, r: -1, atMs: 12_000 }, { q: 4, r: 0, atMs: 30_000 }];
const slow = (from: { q: number; r: number }) => [{ q: from.q, r: from.r, atMs: 0 }, { q: from.q + 1, r: -1, atMs: 20_000 }, { q: 4, r: 0, atMs: 45_000 }];
const flat = (path: { q: number; r: number; atMs: number }[] | null) => path?.map((s) => [s.q, s.r, s.atMs]) ?? null;

describe('going round a fire, or waiting it out', () => {
  it('goes round from where it is: walking back from a fire ahead, a horde swerving on', () => {
    expect(flat(detour(road, 14_000, hex(2, 0), around))).toEqual([[0, 0, 0], [1, 0, 10_000], [1, 0, 18_000], [2, -1, 30_000], [4, 0, 48_000]]);
    expect(flat(detour(road, 14_000, hex(2, 0), around, false))).toEqual([[0, 0, 0], [1, 0, 14_000], [2, -1, 26_000], [4, 0, 44_000]]);
    expect(detour(road, 14_000, hex(2, 0), () => null)).toBeNull();
  });

  it('waits in the hex before the fire until it is out', () => {
    expect(flat(waitOut(road, 14_000, hex(2, 0), 60_000))).toEqual([[0, 0, 0], [1, 0, 10_000], [1, 0, 50_000], [2, 0, 60_000], [3, 0, 70_000], [4, 0, 80_000]]);
    expect(flat(withoutHalts(waitOut(road, 14_000, hex(2, 0), 60_000)))).toEqual(flat(road));
  });

  it('takes whichever arrives sooner', () => {
    // A short fire: waiting beats the slow way round.
    expect(flat(bestWay(road, 4_000, hex(3, 0), 35_000, slow))).toEqual([[0, 0, 0], [1, 0, 10_000], [2, 0, 20_000], [2, 0, 25_000], [3, 0, 35_000], [4, 0, 45_000]]);
    // A long one: round it.
    expect(flat(bestWay(road, 4_000, hex(3, 0), 60_000, slow))).toEqual([[0, 0, 0], [1, 0, 10_000], [2, -1, 30_000], [4, 0, 55_000]]);
    // No way round: it waits.
    expect(flat(bestWay(road, 4_000, hex(3, 0), 60_000, () => null))!.at(-1)).toEqual([4, 0, 70_000]);
  });
});
