import { describe, expect, it } from 'vitest';
import type { TerrainId } from '../src/data/index.js';
import { hex } from '../src/sim/hex.js';
import { longestRiver } from '../src/sim/blessings.js';

const lake = (...cells: string[]) => new Map<string, TerrainId>(cells.map((k) => [k, 'lake']));

describe('the longest river line', () => {
  // The edge between (1,0) and (1,-1) has a corner on the lake hex (0,0).
  const mouth = { a: hex(1, 0), b: hex(1, -1) };

  it('counts river edges joined corner to corner', () => {
    expect(longestRiver([], new Map())).toBe(0);
    expect(longestRiver([mouth], new Map())).toBe(1);
  });

  it('runs on into a lake, to its farthest corner', () => {
    // One lake hex: the opposite corner is 3 edges round it.
    expect(longestRiver([mouth], lake('0,0'))).toBe(1 + 3);
    // Lakes that touch are one lake: the farthest corner is further on.
    expect(longestRiver([mouth], lake('0,0', '-1,0', '-2,0'))).toBe(1 + 7);
  });
});
