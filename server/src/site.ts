// The hand-updated support data (§11.8): this month's server costs, the
// donations received, what carried in from last month, and the donation link.
// Kept in site/costs.json at the repository root so the developer edits one
// small file each month and no redeploy is needed.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const COSTS_FILE = fileURLToPath(new URL('../../site/costs.json', import.meta.url));

export interface Costs {
  month: string;
  currency: string;
  costs: number;
  donations: number;
  carryIn: number;
  donationUrl: string;
  note?: string;
}

const FALLBACK: Costs = {
  month: '',
  currency: 'EUR',
  costs: 0,
  donations: 0,
  carryIn: 0,
  donationUrl: 'https://ko-fi.com/',
};

/** Reads site/costs.json; a missing or broken file reads as all zeroes. */
export function loadCosts(): Costs {
  try {
    const parsed = JSON.parse(readFileSync(COSTS_FILE, 'utf8')) as Partial<Costs>;
    return { ...FALLBACK, ...parsed };
  } catch {
    return FALLBACK;
  }
}
