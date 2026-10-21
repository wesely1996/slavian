import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { CLIENT_DATA, CLIENT_NOTICES, clientData, clientNotices, MAPGEN_FIXTURE, mapgenVectors, NOTICE_FIXTURE, noticeVectors } from '../src/fixtures.js';

describe('shared fixtures for the client local engine', () => {
  it('are up to date with the server rules (npm run fixtures)', () => {
    const stored = JSON.parse(readFileSync(MAPGEN_FIXTURE, 'utf8'));
    expect(stored).toEqual(JSON.parse(JSON.stringify(mapgenVectors(loadGameData()))));
  });

  it('bundle the game data into the app as the server reads it (npm run fixtures)', () => {
    expect(readFileSync(CLIENT_DATA, 'utf8')).toBe(clientData(loadGameData()));
  });

  it('bundle the notice translations into the app (npm run fixtures)', () => {
    expect(readFileSync(CLIENT_NOTICES, 'utf8')).toBe(clientNotices());
    expect(JSON.parse(readFileSync(NOTICE_FIXTURE, 'utf8'))).toEqual(JSON.parse(JSON.stringify(noticeVectors())));
  });
});
