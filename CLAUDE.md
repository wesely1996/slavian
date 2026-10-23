# Slavian — notes for Claude

- Design and roadmap: `PLAN.md`. Setup, CI/CD: `README.md`.
- **All changes go on a feature branch and are merged into `main` through a pull request.** Never push to `main` directly.
- PRs are **squash-merged** and their branch is **deleted** after merging. Claude may merge its own PRs this way once CI is green. Start every follow-up from the latest `main` (a reused branch name is recreated from `main`, never stacked on the squashed history).
- Before pushing: `cd server && npm run typecheck && npm test` (set `TEST_DATABASE_URL` for the Postgres tests), and the Godot headless tests (`godot --headless --path client --script res://tests/test_runner.gd`).
- Hex math exists in both `server/src/sim/hex.ts` and `client/scripts/hex/hex_math.gd`; change both and keep `data/fixtures/hex-vectors.json` passing on both sides.
- The solo engine (`client/scripts/local/`) must answer like the server: a new rule or route comes with a scenario step (`server/test/*-scenario.test.ts`, re-record with `UPDATE_FIXTURES=1`); `server/test/parity.test.ts` fails on routes or plot kinds no scenario plays.
