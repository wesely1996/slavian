// Errors that map to client-facing HTTP statuses.

// A game rule was broken (not enough resources, queue full, ...): 400.
export class RuleError extends Error {}

export class NotFoundError extends Error {}

export class ForbiddenError extends Error {}

export class UnauthorizedError extends Error {}
