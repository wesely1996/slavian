// Sends 'push' notifications to players' devices, holding them through
// quiet hours and dropping ones that waited too long.
import type { GameData } from '../data/index.js';
import { deviceTokens, forgetDevice, loadPrefs, markPushed, unpushed } from '../db/notifications.js';
import { inTransaction, type Db } from '../db/pool.js';
import { inQuietHours, pushWanted } from '../sim/notifications.js';
import type { PushSender } from './sender.js';

const MS_PER_HOUR = 3_600_000;

// One pass; returns how many went out.
export async function pushPending(db: Db, data: GameData, sender: PushSender | null, now: Date): Promise<number> {
  return inTransaction(db, async (client) => {
    let sent = 0;
    for (const n of await unpushed(client)) {
      const expired = now.getTime() - n.createdAt.getTime() > data.notifications.pushExpiryHours * MS_PER_HOUR;
      const prefs = await loadPrefs(client, n.accountId);
      // A topic switched off: marked pushed, never sent.
      const wanted = !expired && pushWanted(data.notifications.topics, prefs, n.kind);
      const tokens = sender && wanted ? await deviceTokens(client, n.accountId) : [];
      if (tokens.length && inQuietHours(now, prefs)) continue;
      if (tokens.length) {
        const invalid = await sender!.send(tokens, {
          title: n.title,
          body: n.body,
          data: { worldId: String(n.worldId), kind: n.kind },
        });
        for (const token of invalid) await forgetDevice(client, token);
        sent += 1;
      }
      await markPushed(client, n.id, now);
    }
    return sent;
  });
}

export async function runPushLoop(
  db: Db,
  data: GameData,
  sender: PushSender | null,
  options: { pollMs: number; signal: AbortSignal },
): Promise<void> {
  while (!options.signal.aborted) {
    try {
      await pushPending(db, data, sender, new Date());
    } catch (error) {
      console.error('Push failed:', error);
    }
    await new Promise((resolve) => setTimeout(resolve, options.pollMs));
  }
}
