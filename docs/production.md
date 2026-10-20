# Running Slavian in production

PLAN.md M5 step 17. The playtest setup (`docs/playtest.md`) runs the server on
your own computer behind a Cloudflare quick tunnel. Production runs it on a
small server (VPS) with its own domain and HTTPS, nightly backups, error
alerts and an uptime check. The database stays on Neon, or can run on the
same machine.

## What runs where

| Piece | Where | Notes |
|---|---|---|
| Game server | `ops/production/docker-compose.yml`, service `server` | The image CI publishes on every merge to main: `ghcr.io/wesely1996/slavian-server:main`, plus one tagged with the commit's sha. |
| HTTPS | service `caddy` | Fetches and renews the certificate for `DOMAIN` by itself; the live WebSocket passes through. |
| Database | Neon (`DATABASE_URL`) | Use Neon's *direct* connection string, not the pooled one. `--profile local-db` runs Postgres on the VPS instead. |
| Backups | service `backup` | A `pg_dump` every night into `ops/production/backups/`, the last 14 days kept. Neon's point-in-time restore comes on top. |
| Push | `fcm.json` beside the compose file | The Firebase service-account key (`docs/push.md`), never baked into the image. |
| Costs | `costs.json` beside the compose file | A copy of `site/costs.json`, edited each month without a redeploy. |

## First deployment

1. **A VPS** with Docker. A 1 vCPU / 1 GB machine is enough to start (Hetzner CX22, a DigitalOcean basic droplet). Open ports 80 and 443.
2. **A domain:** point an `A` (and `AAAA`) record such as `play.example.com` at the VPS.
3. **The image:** the first merge to main after this step publishes it.
   - The package is private at first. Either make it public (GitHub → your profile → Packages → slavian-server → Package settings → Change visibility), or on the VPS run `docker login ghcr.io` with a token that has `read:packages`.
4. **The files**, on the VPS:
   ```sh
   git clone https://github.com/wesely1996/slavian.git && cd slavian/ops/production
   cp .env.example .env              # DOMAIN, DATABASE_URL, ALERT_WEBHOOK_URL…
   cp ../../site/costs.json costs.json
   cp ~/fcm.json fcm.json            # optional: push notifications
   docker compose up -d
   ```
5. **Check:**
   - `curl https://play.example.com/health` answers `{"ok":true}`.
   - Set `REMOTE_SERVER_URL` in `client/scripts/net/session.gd` to `https://play.example.com`: every exported build talks to it, with no address to type.

## Updates

Every merge to main publishes a new `main` image. To run it:

```sh
cd slavian/ops/production && git pull && docker compose pull && docker compose up -d
```

The server applies new database migrations on start. To go back to an
earlier build, set `SLAVIAN_TAG=<commit sha>` in `.env` and run
`docker compose up -d`.

## Backups

- Nightly at `BACKUP_HOUR` (UTC), into `ops/production/backups/slavian-<date>.dump`.
- Back up by hand: `docker compose run --rm -e BACKUP_ONCE=1 backup`.
- Restore into an empty database:
  ```sh
  pg_restore --clean --if-exists --no-owner -d "$DATABASE_URL" backups/slavian-20261020-0300.dump
  ```
- Copy the backups off the machine now and then, for example with `rclone` to cloud storage. A backup on the same disk doesn't survive losing the VPS.
- On Neon, its point-in-time restore (the history window of your plan) is the faster way back from a bad migration or a mistake.

## Errors and uptime

- **Alerts:** set `ALERT_WEBHOOK_URL` to a Discord or Slack incoming webhook. These post a line to it:
  - a failed scheduler event or scheduler pass;
  - a server error (HTTP 500);
  - a crash;
  - a failed backup.

  The same kind of alert goes out at most once every 10 minutes (`ALERT_EVERY_MINUTES`). `ALERT_NAME` tags the messages (for example `prod`).
- **Uptime:** point a free uptime monitor at `https://<DOMAIN>/health`, for example UptimeRobot or Better Stack every 5 minutes, with mail or app alerts. The check answers 503 when the database doesn't.
- **Logs:** `docker compose logs -f server`. They are rotated at 5 × 20 MB.

## Telemetry

The server records how runs go (PLAN.md §13), with no personal data: only a world's id, counts and outcomes.

| Event | What it records |
|---|---|
| `run_start` | players, difficulty, speed and fronts |
| `run_end` | outcome; the front that struck the last blow on a loss; days; bridge stage; Sanctity; waves beaten and faced; camps, sites, scrolls and villages |
| `wave_result` | each wave's battle: wave, front, threat, where (village, field or Holy City), held, raided or razed, rounds, the sizes of both sides, wall level |

Read a summary of the last 30 days with the win rate, losses by front, mean bridge stage and wave results by front:

```sh
docker compose exec server npm run telemetry -- 30
```
