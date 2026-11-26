import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { batchTries, groupName, missingUnits, validateComposition } from '../src/sim/armyGroups.js';

const data = loadGameData();

describe('army groups', () => {
  it('are named, or named after their home', () => {
    expect(groupName('  Iron Guard ', 'Krasnogor')).toBe('Iron Guard');
    expect(groupName('', 'Krasnogor')).toBe("Krasnogor's Army");
    expect(groupName(undefined, 'Krasnogor')).toBe("Krasnogor's Army");
    expect(() => groupName('x'.repeat(33), 'Krasnogor')).toThrow(/at most 32/);
  });

  it('hold soldiers and scouts that march, by name, within the limit', () => {
    expect(Object.keys(validateComposition(data, { spearman: 4, archer: 2, scout: 1, axeman: 0 }))).toEqual(['archer', 'scout', 'spearman']);
    expect(() => validateComposition(data, { settler: 2 })).toThrow(/don't march/);
    expect(() => validateComposition(data, { scout: 3 })).toThrow(/at least one soldier/);
    expect(() => validateComposition(data, { spearman: 1.5 })).toThrow(/whole numbers/);
    expect(() => validateComposition(data, { spearman: data.armies.groups.maxUnits + 1 })).toThrow(/at most/);
  });

  it('lack what neither the army nor the troops on their way hold', () => {
    expect(missingUnits({ spearman: 10, archer: 4 }, { spearman: 6 }, { spearman: 2, archer: 4 })).toEqual({ spearman: 2 });
    expect(missingUnits({ spearman: 10 }, { spearman: 12 }, {})).toEqual({});
  });

  it('try ever smaller batches, from what is missing (at most a batch) down to one', () => {
    expect(batchTries(10, 100)).toEqual([10, 5, 2, 1]);
    expect(batchTries(300, 100)).toEqual([100, 50, 25, 12, 6, 3, 1]);
    expect(batchTries(1, 100)).toEqual([1]);
  });
});
