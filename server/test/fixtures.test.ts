import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { CLIENT_DATA, clientData, MAPGEN_FIXTURE, mapgenVectors } from '../src/fixtures.js';

describe('shared fixtures for the client local engine', () => {
  it('are up to date with the server rules (npm run fixtures)', () => {
    const stored = JSON.parse(readFileSync(MAPGEN_FIXTURE, 'utf8'));
    expect(stored).toEqual(JSON.parse(JSON.stringify(mapgenVectors(loadGameData()))));
  });

  it('bundle the game data into the app as the server reads it (npm run fixtures)', () => {
    expect(readFileSync(CLIENT_DATA, 'utf8')).toBe(clientData(loadGameData()));
  });
});
