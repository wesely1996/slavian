// The Market's bounty board (data/buildings.json village.market.bounties):
// a poster pays what they offer plus a fee at once; whoever takes the
// bounty pays what is asked and gets what is offered, and the poster gets
// what was asked less the fee. All of the fee falls on the poster.
import type { GameData } from '../data/index.js';
import { RuleError } from '../errors.js';
import { mapResources, RESOURCE_KINDS, type Resources } from './resources.js';
import { total } from './logistics.js';

// The fee on what is offered, paid when posting (rounded up).
export function bountyFee(data: GameData, offer: Resources): Resources {
  const share = data.buildings.village.market.bounties.feeShare;
  // (A hair off before rounding: 300 × 0.1 is 30.000000000000004 in floats.)
  return mapResources((k) => Math.ceil(offer[k] * share - 1e-9));
}

// What the poster gets when the bounty is taken: what was asked, less the fee.
export function bountyReturn(data: GameData, want: Resources): Resources {
  const share = data.buildings.village.market.bounties.feeShare;
  return mapResources((k) => Math.floor(want[k] * (1 - share) + 1e-9));
}

// How many open bounties a Market of this level keeps.
export function bountySlots(data: GameData, marketLevel: number): number {
  return marketLevel > 0 ? 1 + Math.floor((marketLevel - 1) / data.buildings.village.market.bounties.levelsPerBounty) : 0;
}

// The most a bounty offers, and asks, in all.
export function bountyMost(data: GameData, marketLevel: number): number {
  return data.buildings.village.market.bounties.amountPerLevel * marketLevel;
}

// Checks a bounty before it is posted.
export function checkBounty(data: GameData, marketLevel: number, open: number, offer: Resources, want: Resources, items: readonly string[] = []): void {
  if (marketLevel <= 0) throw new RuleError('Build a Market to post bounties');
  for (const side of [offer, want]) {
    if (RESOURCE_KINDS.some((k) => !Number.isInteger(side[k]) || side[k] < 0)) throw new RuleError('Amounts are whole, non-negative numbers');
  }
  if (total(offer) <= 0 && items.length === 0) throw new RuleError('Offer something');
  if (items.some((item) => !data.heroes.items[item])) throw new RuleError('No such gear');
  if (total(want) <= 0) throw new RuleError('Ask for something');
  if (RESOURCE_KINDS.some((k) => offer[k] > 0 && want[k] > 0)) throw new RuleError('Offer and ask for different resources');
  const most = bountyMost(data, marketLevel);
  if (total(offer) > most || total(want) > most) throw new RuleError(`The Market takes bounties of at most ${most} on each side`);
  const slots = bountySlots(data, marketLevel);
  if (open >= slots) throw new RuleError(`The Market keeps ${slots} open ${slots === 1 ? 'bounty' : 'bounties'}`);
}
