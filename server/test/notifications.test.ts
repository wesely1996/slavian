import { generateKeyPairSync } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { FcmSender } from '../src/push/sender.js';
import { DEFAULT_PREFS, digestSummary, inQuietHours, nextDigestAt } from '../src/sim/notifications.js';

const at = (iso: string) => new Date(iso);

describe('quiet hours and the digest', () => {
  const night = { ...DEFAULT_PREFS, quietStart: 22 * 60, quietEnd: 7 * 60 };

  it('quiet hours can wrap past midnight, in local time', () => {
    expect(inQuietHours(at('2026-06-01T23:00:00Z'), night)).toBe(true);
    expect(inQuietHours(at('2026-06-01T06:59:00Z'), night)).toBe(true);
    expect(inQuietHours(at('2026-06-01T07:00:00Z'), night)).toBe(false);
    expect(inQuietHours(at('2026-06-01T12:00:00Z'), night)).toBe(false);
    // UTC+2: 21:00 UTC is 23:00 local.
    expect(inQuietHours(at('2026-06-01T21:00:00Z'), { ...night, utcOffsetMinutes: 120 })).toBe(true);
    expect(inQuietHours(at('2026-06-01T23:00:00Z'), DEFAULT_PREFS)).toBe(false);
    expect(inQuietHours(at('2026-06-01T13:30:00Z'), { ...DEFAULT_PREFS, quietStart: 13 * 60, quietEnd: 14 * 60 })).toBe(true);
  });

  it('the digest comes at the next digest hour, local time', () => {
    expect(nextDigestAt(at('2026-06-01T10:00:00Z'), DEFAULT_PREFS)).toEqual(at('2026-06-01T18:00:00Z'));
    expect(nextDigestAt(at('2026-06-01T18:00:00Z'), DEFAULT_PREFS)).toEqual(at('2026-06-02T18:00:00Z'));
    expect(nextDigestAt(at('2026-06-01T19:30:00Z'), DEFAULT_PREFS)).toEqual(at('2026-06-02T18:00:00Z'));
    // UTC+2 at 18:00 local is 16:00 UTC.
    expect(nextDigestAt(at('2026-06-01T10:00:00Z'), { ...DEFAULT_PREFS, utcOffsetMinutes: 120 })).toEqual(at('2026-06-01T16:00:00Z'));
  });

  it('sums up what happened', () => {
    expect(digestSummary(['build_done', 'build_done', 'research_done', 'odd'])).toBe('2 builds finished, 1 tech researched, 1 update');
  });
});

describe('Firebase Cloud Messaging', () => {
  it('signs in with the service account and reports dead tokens', async () => {
    const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
    const calls: { url: string; init: RequestInit }[] = [];
    const fake = (async (url: string, init: RequestInit) => {
      calls.push({ url, init });
      if (url.includes('oauth2')) return new Response(JSON.stringify({ access_token: 'abc', expires_in: 3600 }), { status: 200 });
      const token = JSON.parse(init.body as string).message.token;
      return new Response('{}', { status: token === 'dead-token' ? 404 : 200 });
    }) as unknown as typeof fetch;
    const sender = new FcmSender(
      { project_id: 'slavian-test', client_email: 'push@slavian-test.iam', private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString() },
      fake,
    );
    const invalid = await sender.send(['good-token', 'dead-token'], { title: 'Horde', body: 'Soon', data: { worldId: '1' } });
    expect(invalid).toEqual(['dead-token']);
    expect(calls.filter((c) => c.url.includes('oauth2'))).toHaveLength(1);
    const send = calls.find((c) => c.url.includes('messages:send'))!;
    expect(send.url).toBe('https://fcm.googleapis.com/v1/projects/slavian-test/messages:send');
    expect((send.init.headers as Record<string, string>).authorization).toBe('Bearer abc');
    expect(JSON.parse(send.init.body as string).message.notification).toEqual({ title: 'Horde', body: 'Soon' });
  });
});
