// The solo engine plays by the server's rules only where a scenario
// (scenario.ts) has recorded the server's answers for it to match. This
// keeps the scenarios covering the game: every API route is played by one,
// unless it is listed below as one a solo world never calls, and builds go
// to every kind of plot (their shapes are checked before the rules are).
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const FIXTURES = fileURLToPath(new URL('../../data/fixtures/', import.meta.url));
const API = fileURLToPath(new URL('../src/api/', import.meta.url));

// Routes a solo world never calls, and why.
const SERVER_ONLY: Record<string, string> = {
  'GET /health': 'the health check',
  'GET /v1/costs': 'server costs and donations (the start screen)',
  'GET /v1/data': 'the solo engine bundles the game data',
  'POST /v1/auth/guest': 'accounts',
  'GET /v1/me': 'accounts',
  'PATCH /v1/me': 'accounts',
  'DELETE /v1/me': 'accounts',
  'GET /v1/me/export': 'accounts',
  'GET /v1/me/notifications': 'push settings (a solo world sends no pushes)',
  'PATCH /v1/me/notifications': 'push settings (a solo world sends no pushes)',
  'POST /v1/me/devices': 'push devices',
  'POST /v1/reports': 'bug reports go to the server',
  'POST /v1/worlds': 'a solo world starts in the app (start-world.json checks it)',
  'POST /v1/worlds/join': 'joining a group',
  'POST /v1/worlds/:id/start': 'a solo world starts in the app (start-world.json checks it)',
  'PUT /v1/worlds/:id/hero': 'the hero is picked before a solo world starts',
  'PUT /v1/worlds/:id/clan': 'the clan is picked before a solo world starts',
  'POST /v1/worlds/:id/leave': 'leaving a group (a solo world is deleted instead)',
  'PUT /v1/worlds/:id/delegation': 'delegating to a teammate',
  'DELETE /v1/worlds/:id/delegation': 'delegating to a teammate',
};

// Every route the API declares, as "METHOD /path/:param".
function routes(): string[] {
  const found = new Set<string>();
  for (const file of readdirSync(API).filter((f) => f.endsWith('.ts'))) {
    for (const [, method, path] of readFileSync(API + file, 'utf8').matchAll(/app\.(get|post|put|patch|delete)\('([^']+)'/g)) {
      found.add(`${method!.toUpperCase()} ${path}`);
    }
  }
  return [...found].sort();
}

type Step = { method?: string; path?: string; body?: Record<string, unknown> };
function steps(): Step[] {
  return readdirSync(FIXTURES)
    .filter((f) => f.endsWith('-scenario.json'))
    .flatMap((f) => (JSON.parse(readFileSync(FIXTURES + f, 'utf8')) as { steps: Step[] }).steps)
    .filter((s) => s.method && s.path);
}

function matches(route: string, step: Step): boolean {
  const [method, path] = route.split(' ');
  const pattern = new RegExp(`^${path!.replace(/:\w+/g, '[^/]+')}$`);
  return method === step.method && pattern.test(step.path!.split('?')[0]!);
}

describe('server and solo engine parity', () => {
  const all = routes();
  const played = steps();

  it('plays every route in a scenario, or names it server-only', () => {
    const missing = all.filter((r) => !(r in SERVER_ONLY) && !played.some((s) => matches(r, s)));
    expect(missing, 'routes no scenario plays (add them to one, or to SERVER_ONLY)').toEqual([]);
    expect(Object.keys(SERVER_ONLY).filter((r) => !all.includes(r)), 'SERVER_ONLY names routes that no longer exist').toEqual([]);
  });

  it('only plays routes the server has', () => {
    const unknown = played.filter((s) => !all.some((r) => matches(r, s))).map((s) => `${s.method} ${s.path}`);
    expect(unknown).toEqual([]);
  });

  it('builds on every kind of plot', () => {
    const plots = played.filter((s) => s.path!.endsWith('/build') && typeof s.body?.plot === 'string').map((s) => String(s.body!.plot));
    const kind = (plot: string) => (/^o-?\d/.test(plot) ? 'o' : plot.replace(/\d+$/, ''));
    expect(new Set(plots.map(kind))).toEqual(new Set(['f', 'c', 'w', 't', 'o']));
  });
});
