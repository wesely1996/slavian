// Error alerts (PLAN.md M5 step 17): a failed scheduler event, a failed
// scheduler pass, a server error or a crash posts one line to
// ALERT_WEBHOOK_URL, a Discord or Slack incoming webhook (both read the same
// body), so the developer hears of it without watching the logs. The same
// kind of alert goes out at most once every ALERT_EVERY_MINUTES (default 10);
// without a webhook nothing is sent. Alerts never throw.

type Fetch = (url: string, init: { method: string; headers: Record<string, string>; body: string }) => Promise<unknown>;

const lastSent = new Map<string, number>();

export interface AlertOptions {
  env?: NodeJS.ProcessEnv;
  now?: number;
  fetch?: Fetch;
}

/** Sends `message` under `key` unless that key was sent recently; true when sent. */
export async function alert(key: string, message: string, options: AlertOptions = {}): Promise<boolean> {
  const env = options.env ?? process.env;
  const url = env.ALERT_WEBHOOK_URL;
  if (!url) return false;
  const now = options.now ?? Date.now();
  const every = Number(env.ALERT_EVERY_MINUTES ?? 10) * 60_000;
  const last = lastSent.get(key);
  if (last !== undefined && now - last < every) return false;
  lastSent.set(key, now);
  const text = `[slavian${env.ALERT_NAME ? ` ${env.ALERT_NAME}` : ''}] ${message}`.slice(0, 1900);
  try {
    await (options.fetch ?? (fetch as unknown as Fetch))(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ content: text, text }),
    });
    return true;
  } catch (error) {
    console.error('Alert not sent:', error);
    return false;
  }
}

/** Forgets what was sent (tests). */
export function resetAlerts(): void {
  lastSent.clear();
}
