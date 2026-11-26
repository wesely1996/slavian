// A new release, announced once to every registered phone. The release
// workflow bakes the version and where to download it into the server image
// (SLAVIAN_VERSION, SLAVIAN_RELEASES_URL); a server started on a version not
// yet announced pushes "Slavian <version> is out" to all devices. Without a
// version (a dev build, a local run) nothing is announced.
import { inTransaction, type Db } from '../db/pool.js';
import type { PushSender } from './sender.js';

export interface Release {
  version: string;
  url: string;
  // The release's own files, for the app to update itself: the Android APK
  // and the Windows build (a zip holding Slavian.exe).
  assets: { android: string; windows: string };
}

export function releaseFromEnv(env: NodeJS.ProcessEnv = process.env): Release | null {
  const version = env.SLAVIAN_VERSION?.trim();
  if (!version) return null;
  // Where the release workflow uploads them (release.yml): slavian-<v>.apk
  // and slavian-<v>-windows.zip under the release's tag.
  const files = (env.SLAVIAN_ASSETS_URL?.trim() || 'https://github.com/wesely1996/slavian/releases/download/v{version}').replaceAll('{version}', version);
  return {
    version,
    url: env.SLAVIAN_RELEASES_URL?.trim() || 'https://github.com/wesely1996/slavian/releases/latest',
    assets: { android: `${files}/slavian-${version}.apk`, windows: `${files}/slavian-${version}-windows.zip` },
  };
}

// What the push says. Phones on older versions do nothing when it is
// tapped, so the address is in the text itself.
export function releaseMessage(release: Pick<Release, 'version' | 'url'>) {
  return {
    title: `Slavian ${release.version} is out`,
    body: `A new version is ready. Download it at ${release.url.replace(/^https?:\/\//, '')}`,
    data: { kind: 'release', version: release.version, url: release.url },
  };
}

// Returns how many devices it went to; 0 when already announced (or no one
// to tell). A failed send rolls back, so the next start tries again.
export async function announceRelease(db: Db, sender: PushSender | null, release: Pick<Release, 'version' | 'url'> | null, now: Date): Promise<number> {
  if (!release || !sender) return 0;
  return inTransaction(db, async (client) => {
    const fresh = await client.query(
      'INSERT INTO release_announcements (version, announced_at) VALUES ($1, $2) ON CONFLICT DO NOTHING RETURNING version',
      [release.version, now],
    );
    if (!fresh.rowCount) return 0;
    const tokens = (await client.query<{ token: string }>('SELECT token FROM devices ORDER BY created_at')).rows.map((r) => r.token);
    if (!tokens.length) return 0;
    const invalid = await sender.send(tokens, releaseMessage(release));
    if (invalid.length) await client.query('DELETE FROM devices WHERE token = ANY($1)', [invalid]);
    return tokens.length - invalid.length;
  });
}
