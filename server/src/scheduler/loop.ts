import type { Db } from '../db/pool.js';
import type { SchedulerDeps } from './events.js';
import { tick } from './worker.js';
import { alert } from '../alerts.js';

// Polls for due events until `signal` aborts.
export async function runWorkerLoop(
  db: Db,
  deps: SchedulerDeps,
  options: { pollMs: number; signal: AbortSignal },
): Promise<void> {
  while (!options.signal.aborted) {
    try {
      const result = await tick(db, new Date(), deps);
      if (result.events > 0 || result.skipped > 0) console.log('scheduler', result);
    } catch (error) {
      console.error('Scheduler tick failed:', error);
      void alert('tick', `Scheduler pass failed: ${error instanceof Error ? error.message : String(error)}`);
    }
    await new Promise((resolve) => setTimeout(resolve, options.pollMs));
  }
}
