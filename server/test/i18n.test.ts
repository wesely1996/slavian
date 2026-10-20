import { describe, expect, it } from 'vitest';
import { localize, parsePo } from '../src/i18n.js';
import { digestSummary } from '../src/sim/notifications.js';

describe('server notices', () => {
  it('stay English for English readers', () => {
    expect(localize('en', 'The {threat} {front} horde arrives in about {hours} hours. Check the garrison and its stance.', { threat: 'severe', front: 'north', hours: 3 })).toBe(
      'The severe north horde arrives in about 3 hours. Check the garrison and its stance.',
    );
  });

  it('render in Serbian, with the values filled into them', () => {
    expect(localize('sr_Latn', 'The {threat} {front} horde arrives in about {hours} hours. Check the garrison and its stance.', { threat: 'severe', front: 'north', hours: 3 })).toBe(
      'Dolazi teška horda sa severa, za oko 3 h. Proveri posadu i njen stav.',
    );
    expect(localize('sr', '{enemy} against {defenders}, with {ground}.', { enemy: 40, defenders: 30, ground: 'an ambush, a fort' })).toBe('40 protiv 30, uz zasedu, utvrdu.');
    // Names players chose stay as they are.
    expect(localize('sr', '{village} held', { village: 'Vesnino selo' })).toBe('Vesnino selo se održalo');
  });

  it('fall back to the client catalog for the game data', () => {
    // A threat level and a run's ending, translated only in the catalog.
    expect(localize('sr', '{threat}', { threat: 'Moderate' })).not.toBe('Moderate');
    expect(localize('sr', 'The Holy City has fallen')).not.toBe('The Holy City has fallen');
  });

  it('read gettext catalogs, multi-line entries included', () => {
    const po = 'msgid ""\nmsgstr ""\n"Language: sr\\n"\n\nmsgid "Ritual"\nmsgstr "Obred"\n\nmsgid ""\n"A long "\n"text"\nmsgstr ""\n"Dug "\n"tekst"\n\nmsgid "%d day"\nmsgid_plural "%d days"\nmsgstr[0] "%d dan"\n';
    expect(parsePo(po)).toEqual({ Ritual: 'Obred', 'A long text': 'Dug tekst' });
  });

  it('sum up the day in the reader\'s language', () => {
    expect(digestSummary(['build_done', 'build_done', 'research_done'], 'sr_Latn')).toBe('Završene gradnje: 2, istražene tehnologije: 1');
  });
});
