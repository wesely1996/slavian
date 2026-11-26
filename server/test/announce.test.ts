// A release announced once to every registered phone (push/announce.ts).
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createGuestAccount } from '../src/db/accounts.js';
import { registerDevice } from '../src/db/notifications.js';
import { inTransaction, type Db } from '../src/db/pool.js';
import { announceRelease, releaseFromEnv, releaseMessage } from '../src/push/announce.js';
import type { PushMessage, PushSender } from '../src/push/sender.js';
import { createTestDb, TEST_DATABASE_URL } from './db.js';

class FakeSender implements PushSender {
  sent: { tokens: readonly string[]; message: PushMessage }[] = [];
  constructor(private readonly gone: string[] = [], private readonly fail = false) {}
  async send(tokens: readonly string[], message: PushMessage): Promise<string[]> {
    if (this.fail) throw new Error('FCM send failed: 500');
    this.sent.push({ tokens, message });
    return this.gone;
  }
}

describe('release from the environment', () => {
  it('needs a version; the address defaults to the latest release', () => {
    expect(releaseFromEnv({})).toBeNull();
    expect(releaseFromEnv({ SLAVIAN_VERSION: ' ' })).toBeNull();
    expect(releaseFromEnv({ SLAVIAN_VERSION: '0.17.0' })).toEqual({
      version: '0.17.0',
      url: 'https://github.com/wesely1996/slavian/releases/latest',
      assets: {
        android: 'https://github.com/wesely1996/slavian/releases/download/v0.17.0/slavian-0.17.0.apk',
        windows: 'https://github.com/wesely1996/slavian/releases/download/v0.17.0/slavian-0.17.0-windows.zip',
      },
    });
    expect(releaseFromEnv({ SLAVIAN_VERSION: '0.17.0', SLAVIAN_ASSETS_URL: 'https://example.org/{version}' })?.assets.android).toBe('https://example.org/0.17.0/slavian-0.17.0.apk');
    expect(releaseFromEnv({ SLAVIAN_VERSION: '0.17.0', SLAVIAN_RELEASES_URL: 'https://example.org/r' })?.url).toBe('https://example.org/r');
  });

  it('says where to download it in the text', () => {
    const message = releaseMessage({ version: '0.17.0', url: 'https://github.com/wesely1996/slavian/releases/latest' });
    expect(message.title).toBe('Slavian 0.17.0 is out');
    expect(message.body).toContain('github.com/wesely1996/slavian/releases/latest');
    expect(message.data).toMatchObject({ kind: 'release', version: '0.17.0' });
  });
});

describe.skipIf(!TEST_DATABASE_URL)('release announcements (postgres)', () => {
  let db: Db;
  let cleanup: () => Promise<void>;
  const now = new Date('2026-11-18T07:00:00Z');
  const release = { version: '0.17.0', url: 'https://github.com/wesely1996/slavian/releases/latest' };

  beforeAll(async () => {
    ({ db, cleanup } = await createTestDb());
    await inTransaction(db, async (client) => {
      const { account: a } = await createGuestAccount(client, 'A');
      const { account: b } = await createGuestAccount(client, 'B');
      await registerDevice(client, a.id, 'token-a', 'android');
      await registerDevice(client, b.id, 'token-b', 'android');
      await registerDevice(client, b.id, 'token-gone', 'android');
    });
  });
  afterAll(async () => cleanup?.());

  it('does nothing without a version or a way to push', async () => {
    expect(await announceRelease(db, new FakeSender(), null, now)).toBe(0);
    expect(await announceRelease(db, null, release, now)).toBe(0);
    expect((await db.query('SELECT * FROM release_announcements')).rowCount).toBe(0);
  });

  it('tries again on the next start when the send fails', async () => {
    await expect(announceRelease(db, new FakeSender([], true), release, now)).rejects.toThrow('FCM');
    expect((await db.query('SELECT * FROM release_announcements')).rowCount).toBe(0);
  });

  it('tells every phone once, and forgets the ones gone', async () => {
    const sender = new FakeSender(['token-gone']);
    expect(await announceRelease(db, sender, release, now)).toBe(2);
    expect(sender.sent).toHaveLength(1);
    expect([...sender.sent[0]!.tokens].sort()).toEqual(['token-a', 'token-b', 'token-gone']);
    expect((await db.query('SELECT token FROM devices ORDER BY token')).rows.map((r) => r.token)).toEqual(['token-a', 'token-b']);
    // Restarted on the same version: no second push.
    const again = new FakeSender();
    expect(await announceRelease(db, again, release, now)).toBe(0);
    expect(again.sent).toHaveLength(0);
    // The next version goes out.
    expect(await announceRelease(db, again, { ...release, version: '0.17.1' }, now)).toBe(2);
  });
});
