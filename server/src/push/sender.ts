// Sending push notifications. With an FCM service account configured
// (FCM_SERVICE_ACCOUNT as JSON, or FCM_SERVICE_ACCOUNT_FILE as a path) the
// server pushes through Firebase Cloud Messaging; without one, pushes stay
// in the in-app inbox only.
import { createSign } from 'node:crypto';
import { readFileSync } from 'node:fs';

export interface PushMessage {
  title: string;
  body: string;
  data: Record<string, string>;
}

export interface PushSender {
  // Sends to each token; returns the tokens FCM says are no longer valid.
  send(tokens: readonly string[], message: PushMessage): Promise<string[]>;
}

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const TOKEN_URL = 'https://oauth2.googleapis.com/token';

function base64url(input: string | Buffer): string {
  return Buffer.from(input).toString('base64url');
}

export class FcmSender implements PushSender {
  private accessToken: { value: string; expiresAt: number } | null = null;

  constructor(
    private readonly account: ServiceAccount,
    private readonly fetchFn: typeof fetch = fetch,
  ) {}

  // A signed JWT exchanged for an OAuth access token (RFC 7523).
  private async token(): Promise<string> {
    const now = Math.floor(Date.now() / 1000);
    if (this.accessToken && this.accessToken.expiresAt > now + 60) return this.accessToken.value;
    const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
    const claims = base64url(
      JSON.stringify({ iss: this.account.client_email, scope: SCOPE, aud: TOKEN_URL, iat: now, exp: now + 3600 }),
    );
    const signature = createSign('RSA-SHA256').update(`${header}.${claims}`).sign(this.account.private_key);
    const response = await this.fetchFn(TOKEN_URL, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: `${header}.${claims}.${base64url(signature)}`,
      }),
    });
    if (!response.ok) throw new Error(`FCM auth failed: ${response.status} ${await response.text()}`);
    const body = (await response.json()) as { access_token: string; expires_in: number };
    this.accessToken = { value: body.access_token, expiresAt: now + body.expires_in };
    return body.access_token;
  }

  async send(tokens: readonly string[], message: PushMessage): Promise<string[]> {
    const invalid: string[] = [];
    const url = `https://fcm.googleapis.com/v1/projects/${this.account.project_id}/messages:send`;
    for (const token of tokens) {
      const response = await this.fetchFn(url, {
        method: 'POST',
        headers: { authorization: `Bearer ${await this.token()}`, 'content-type': 'application/json' },
        body: JSON.stringify({
          message: {
            token,
            notification: { title: message.title, body: message.body },
            data: message.data,
            android: { priority: 'high' },
          },
        }),
      });
      if (response.status === 404 || response.status === 400) invalid.push(token);
      else if (!response.ok) throw new Error(`FCM send failed: ${response.status} ${await response.text()}`);
    }
    return invalid;
  }
}

export function pushSenderFromEnv(env: NodeJS.ProcessEnv = process.env): PushSender | null {
  const json = env.FCM_SERVICE_ACCOUNT ?? (env.FCM_SERVICE_ACCOUNT_FILE ? readFileSync(env.FCM_SERVICE_ACCOUNT_FILE, 'utf8') : null);
  if (!json) return null;
  return new FcmSender(JSON.parse(json) as ServiceAccount);
}
