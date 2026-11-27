import { defineConfig } from 'vitest/config';

// Tests that run a world for game days drain many scheduled events (the
// enemy's hourly watch and works among them): room for a slow CI runner.
export default defineConfig({
  test: { testTimeout: 15_000 },
});
