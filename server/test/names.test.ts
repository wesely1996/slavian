import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { isDefaultName, townName } from '../src/sim/names.js';
import { createRng } from '../src/sim/rng.js';

const data = loadGameData();

describe('town names', () => {
  it('gives every town a different name, then makes new ones from roots and endings', () => {
    const rng = createRng(7);
    const taken: string[] = [];
    for (let i = 0; i < data.names.whole.length + 60; i++) taken.push(townName(data, taken, rng));
    expect(new Set(taken.map((n) => n.toLowerCase())).size).toBe(taken.length);
    expect(taken.slice(0, data.names.whole.length).sort()).toEqual([...data.names.whole].sort());
    for (const name of taken.slice(data.names.whole.length)) expect(name).toMatch(/^[A-Z][a-z]+$/);
  });

  it('skips names already taken, whatever their case', () => {
    const taken = data.names.whole.slice(1).map((n) => n.toUpperCase());
    expect(townName(data, taken, createRng(1))).toBe(data.names.whole[0]);
  });

  it('knows the old default names', () => {
    expect(isDefaultName("Mila's village")).toBe(true);
    expect(isDefaultName("Mila's village 3")).toBe(true);
    expect(isDefaultName('Vyshgorod')).toBe(false);
  });
});
