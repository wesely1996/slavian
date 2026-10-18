# Slavian — notes for Claude

- Design and roadmap: `PLAN.md`. Setup, CI/CD: `README.md`.
- **All changes go on a feature branch and are merged into `main` through a pull request.** Never push to `main` directly.
- Before pushing: `cd server && npm run typecheck && npm test` (set `TEST_DATABASE_URL` for the Postgres tests), and the Godot headless tests (`godot --headless --path client --script res://tests/test_runner.gd`).
- Hex math exists in both `server/src/sim/hex.ts` and `client/scripts/hex/hex_math.gd`; change both and keep `data/fixtures/hex-vectors.json` passing on both sides.
