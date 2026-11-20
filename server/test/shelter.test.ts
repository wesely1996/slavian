import { describe, expect, it } from 'vitest';
import { pickShelter } from '../src/scheduler/armies.js';
import { hex } from '../src/sim/hex.js';

const v = (id: number, owner: number | null, q: number, extra: { ruin?: unknown; refuge?: boolean } = {}) => ({ id, ownerAccountId: owner, q, r: 0, ...extra });

describe('an army whose home is razed', () => {
  it('turns for its owner\'s nearest standing village', () => {
    const shelter = pickShelter([v(1, 7, 0, { ruin: {} }), v(2, 7, 9), v(3, 7, 4), v(4, 8, 1)], 7, hex(2, 0));
    expect(shelter).toEqual({ village: v(3, 7, 4), own: true });
  });
  it('with none of its own standing, goes to the nearest ally\'s, before its refugee camp', () => {
    const shelter = pickShelter([v(1, 7, 0, { ruin: {} }), v(2, 7, 1, { refuge: true }), v(3, 8, 9), v(4, 9, 5)], 7, hex(2, 0));
    expect(shelter).toEqual({ village: v(4, 9, 5), own: false });
  });
  it('with no ally\'s either, goes to its refugee camp; with nothing at all, nowhere', () => {
    expect(pickShelter([v(1, 7, 0, { ruin: {} }), v(2, 7, 1, { refuge: true }), v(3, null, 2)], 7, hex(2, 0))).toEqual({ village: v(2, 7, 1, { refuge: true }), own: true });
    expect(pickShelter([v(1, 7, 0, { ruin: {} })], 7, hex(2, 0))).toBeNull();
  });
});
