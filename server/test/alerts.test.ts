import { beforeEach, describe, expect, it } from 'vitest';
import { alert, resetAlerts } from '../src/alerts.js';

describe('alerts', () => {
  beforeEach(resetAlerts);

  it('post to the webhook, at most once a while per kind', async () => {
    const sent: { url: string; body: string }[] = [];
    const fetch = async (url: string, init: { body: string }) => sent.push({ url, body: init.body });
    const env = { ALERT_WEBHOOK_URL: 'https://hooks.example/abc', ALERT_NAME: 'prod' };
    expect(await alert('event:battle_round', 'Event 7 failed', { env, now: 0, fetch })).toBe(true);
    expect(await alert('event:battle_round', 'Event 8 failed', { env, now: 60_000, fetch })).toBe(false);
    expect(await alert('tick', 'Pass failed', { env, now: 60_000, fetch })).toBe(true);
    expect(await alert('event:battle_round', 'Event 9 failed', { env, now: 11 * 60_000, fetch })).toBe(true);
    expect(sent).toHaveLength(3);
    expect(JSON.parse(sent[0]!.body)).toEqual({ content: '[slavian prod] Event 7 failed', text: '[slavian prod] Event 7 failed' });
  });

  it('stay quiet without a webhook, and never throw', async () => {
    expect(await alert('x', 'y', { env: {} })).toBe(false);
    const failing = async () => {
      throw new Error('offline');
    };
    expect(await alert('x', 'y', { env: { ALERT_WEBHOOK_URL: 'https://hooks.example/abc' }, fetch: failing })).toBe(false);
  });
});
