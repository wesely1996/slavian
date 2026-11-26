# Running Slavian in production

PLAN.md M5 step 17. The playtest setup (`docs/playtest.md`) runs the server on
your own computer behind a Cloudflare quick tunnel. Production runs it on a
small server (VPS) with its own domain and HTTPS, nightly backups copied off
the machine, error alerts and an uptime check. The database runs on the same
machine (it can run on Neon instead; "Moving the database here" moves it off).

A release never switches the database. The server keeps using the one its
`.env` names (`DATABASE_URL`); the local Postgres and the off-site copies only
start once `COMPOSE_PROFILES` in that `.env` lists them, and a deploy changes
nothing in it but `SLAVIAN_TAG`. A server still on Neon stays on Neon until
`move-db.sh` is run ("Moving the database here").

## What runs where

| Piece | Where | Notes |
|---|---|---|
| Game server | `ops/production/docker-compose.yml`, service `server` | The image CI publishes on every merge to main: `ghcr.io/wesely1996/slavian-server:main`, plus one tagged with the commit's sha. |
| HTTPS | service `caddy` | Fetches and renews the certificate for `DOMAIN` by itself; the live WebSocket passes through. |
| Database | service `postgres` (profile `local-db`) | Postgres on the VPS, reached only by the other services (no port is open to the internet). Without the profile, `DATABASE_URL` points at a hosted one such as Neon (its *direct* connection string, not the pooled one). |
| Backups | service `backup` | A `pg_dump` every night into `ops/production/backups/`, the last 14 days kept. |
| Off-site backups | service `offsite` (profile `offsite`) | An hour later, the dumps copied to an S3-compatible bucket such as Cloudflare R2, the last 30 days kept there. |
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
   cp .env.example .env              # DOMAIN, POSTGRES_PASSWORD (and the same in DATABASE_URL), OFFSITE_*, ALERT_WEBHOOK_URL…
   cp ../../site/costs.json costs.json
   cp ~/fcm.json fcm.json            # optional: push notifications
   docker compose up -d
   ```
5. **Check:**
   - `curl https://play.example.com/health` answers `{"ok":true}`.
   - Set `REMOTE_SERVER_URL` in `client/scripts/net/session.gd` to `https://play.example.com`: every exported build talks to it, with no address to type.

## Updates

**Releases deploy themselves.** Run **Actions → Release → Run workflow** on
`main` (the version defaults to `config/version` in `client/project.godot`;
the workflow makes the tag), or push a version tag (`git tag v0.2.0
origin/main && git push origin v0.2.0`). Either runs `release.yml`: CI, the
release with the APK attached, the server image `slavian-server:v0.2.0`, and
then the **Deploy to production** job. Don't make the release by hand in
GitHub's UI: a published release is immutable, so the APK can't be added to
it. It SSHes to the VPS and runs `ops/production/deploy.sh
v0.2.0`. The script checks out the tag, pins `SLAVIAN_TAG` in `.env`, pulls
and restarts, and waits up to two minutes for the server to be healthy and
answer `https://<DOMAIN>/health`. If it doesn't, the previous image runs
again and the job fails. Database migrations run on start and are not undone.

**Players hear of it.** The release's server image knows its version
(`SLAVIAN_VERSION`, and `SLAVIAN_RELEASES_URL` for the download page).
Five minutes after the server starts on a version it hasn't announced
(`RELEASE_ANNOUNCE_DELAY_MS`), it pushes "Slavian <version> is out" with
the download address to every registered phone, once (the
`release_announcements` table). That needs push set up (`fcm.json` above):
without it the server logs "Push notifications: off" and nothing goes out.
From 0.17.0, when the server runs a newer version than the app
(`GET /v1/release`), opening the app shows a notice with a Download
button (once a launch), and the main menu offers the download too.

What it needs, once:
- **A deploy key** that may run only the script. On the VPS, in
  `/root/.ssh/authorized_keys`:
  `command="/opt/slavian/ops/production/deploy.sh",restrict ssh-ed25519 AAAA… slavian-release-deploy`.
  Anything sent over that key goes to the script, which accepts nothing but
  `vX.Y.Z`.
- **Repository secrets:** `DEPLOY_SSH_KEY` (the key's private half),
  `DEPLOY_HOST` (the VPS's address) and `DEPLOY_KNOWN_HOSTS` (`ssh-keyscan -t
  ed25519 <host>`, so the job only talks to this machine). Optional variable
  `PRODUCTION_URL` for the link on the run. Without the secrets the job is
  skipped with a warning.
- The job runs in the GitHub environment `production`; add required
  reviewers there (Settings → Environments) to approve each deploy by hand.

**By hand**, the same thing: `/opt/slavian/ops/production/deploy.sh v0.2.0`.
To go back to an earlier release, run it with that tag. To run the latest
`main` between releases (every merge publishes a `main` image), set
`SLAVIAN_TAG=main` in `.env` and run `docker compose pull && docker compose up -d`.

## Moving the database here

From Neon to Postgres on the VPS (`ops/production/move-db.sh`). The game is
down for a few minutes; pick a quiet hour.

1. **The files:** the script comes with the release after this change. Before
   that, in `/opt/slavian`: `git fetch origin && git checkout origin/main`
   (the next release's deploy checks out its tag again).
2. **Docker Compose 2.20 or newer** (`docker compose version`), for the
   services that wait on the database. **Memory:** `free -h`. On a 1 GB
   machine, add swap first (Hetzner's have none), so a busy moment slows the
   server down instead of a process being killed:
   ```sh
   fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
   echo '/swapfile none swap sw 0 0' >> /etc/fstab
   ```
   If memory stays short, Rescale the server to the next size in Hetzner's
   console and raise Postgres's `shared_buffers` and `effective_cache_size` in
   the compose file.
3. **Run it**, in `ops/production`:
   ```sh
   ./move-db.sh
   ```
   It reads Neon's Postgres version and runs the same one here, makes a
   password, stops the game server, backs Neon up, restores the backup here,
   and checks every table's rows against Neon's. Only when they all match
   does it point `.env` at the database here (`DATABASE_URL`,
   `COMPOSE_PROFILES=local-db`; Neon's address stays as
   `HOSTED_DATABASE_URL`, the old file as `.env.before-move`) and start the
   server again. If anything fails, `.env` is put back and the server runs on
   Neon as before. Neon itself is never changed.
4. **Check:** `curl https://<DOMAIN>/health` and play a turn.
5. **Off-site backups:** set the `OFFSITE_*` lines (`.env.example`), add
   `offsite` to `COMPOSE_PROFILES`, `docker compose up -d`, and try one copy:
   `docker compose run --rm -e OFFSITE_ONCE=1 offsite`.
6. **After a week** without trouble, delete the Neon project and cancel its
   plan.

**Going back to Neon** (what was played since the move stays here unless you
restore a fresh backup into Neon first): `cp .env.before-move .env && docker compose up -d`.

## Backups

- Nightly at `BACKUP_HOUR` (UTC), into `ops/production/backups/slavian-<date>.dump`.
- An hour later (`offsite`), copied to the bucket; there the last `OFFSITE_KEEP_DAYS` (30) are kept. A backup on the same disk doesn't survive losing the VPS: keep `offsite` on.
- Back up by hand: `docker compose run --rm -e BACKUP_ONCE=1 backup`; copy off by hand: `docker compose run --rm -e OFFSITE_ONCE=1 offsite`.
- Restore into the database here (the server stopped: `docker compose stop server`):
  ```sh
  docker compose exec -T postgres dropdb -U slavian slavian
  docker compose exec -T postgres createdb -U slavian slavian
  docker compose exec -T postgres pg_restore --no-owner --no-privileges -U slavian -d slavian < backups/slavian-20261020-0300.dump
  docker compose start server
  ```
- A backup from the bucket: download it from the bucket's page (R2: Storage → the bucket → the file) into `ops/production/backups/`, then restore it as above.

## The machine's updates

Ubuntu installs its security updates every day. A few of them (the kernel,
core libraries) only take effect after a restart, which the login banner
shows as "System restart required"; that comes every few weeks. Once, in
`ops/production`:

```sh
./night-reboots.sh
```

It puts the machine on Europe/Belgrade time and turns on the daily updates
with a reboot at 03:00 local time, only on nights when an update waits for
one (`./night-reboots.sh <time zone> <HH:MM>` for others). The game is down
for a minute or two: every service starts again by itself, and the server
catches up on everything that came due. The nightly backup keeps its hour in
UTC (`BACKUP_HOUR`, 03:00 UTC is 04:00 or 05:00 in Belgrade), after the
reboot.

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
