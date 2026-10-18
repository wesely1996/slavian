# Playtest setup

The game server runs in Docker on your computer, the database lives on
[Neon](https://neon.tech) (free, managed, backed up), and a Cloudflare *quick
tunnel* gives the server a public HTTPS address that phones can reach from
anywhere. No domain, Cloudflare account or open router ports needed.

```
phone ──https/wss──▶ *.trycloudflare.com ──tunnel──▶ your computer (Docker: server) ──TLS──▶ Neon Postgres
```

## 1. Database on Neon (once)

1. In the Neon console, create a project (pick the region closest to you).
2. Open **Connect** for the project, **turn off "Connection pooling"**, and copy the connection string.
   It looks like `postgresql://neondb_owner:…@ep-something-123456.eu-central-1.aws.neon.tech/neondb?sslmode=require&channel_binding=require`.
   The host must **not** contain `-pooler`: live updates use `LISTEN`, which pooled connections drop (the server warns at startup if it sees one).
3. Copy `ops/playtest/.env.example` to `ops/playtest/.env` and paste the string as `DATABASE_URL`. `.env` is git-ignored; keep it private.

The server creates its tables on first start.

## 2. Start the server and tunnel

Install [Docker Desktop](https://www.docker.com/products/docker-desktop/), then from the repository folder:

```sh
docker compose -f ops/playtest/docker-compose.yml up -d --build
```

Find the public address in the tunnel's log:

```sh
# macOS / Linux
docker compose -f ops/playtest/docker-compose.yml logs tunnel | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com'
# Windows (PowerShell)
docker compose -f ops/playtest/docker-compose.yml logs tunnel | Select-String trycloudflare.com
```

Check it: opening `https://<address>/health` in a browser shows `{"ok":true}`.

## 3. Play

1. Install the latest **Dev build** APK from the repository's Releases on each phone.
2. In the app, set **Server address** to the `https://….trycloudflare.com` address, enter a name, **Play as guest**.
3. One player creates a world (**Test (10×)** speed for a quick playtest) and shares the invite code; the others **Join**; the host taps **Start the world**.

## Day to day

- **Stopping:** `docker compose -f ops/playtest/docker-compose.yml down`. Nothing is lost: worlds live in Neon, and when the server starts again it processes everything that came due while it was off, in order (builds finish, waves march and fight on schedule).
- **New address after a restart:** quick tunnels get a new random address every time they start. Look it up again (step 2) and in the app tap **Change** next to *Server* on the worlds screen. You stay signed in; accounts live in the database.
- **Updating:** `git pull`, then the same `up -d --build` command.
- **Logs:** `docker compose -f ops/playtest/docker-compose.yml logs -f server`.

## Limits

- The game is only reachable while your computer is on and Docker is running.
- Quick tunnels are meant for testing: no uptime guarantee and a random address. A named tunnel on your own domain (later) gives a fixed address.
- While the server runs, its scheduler polls the database every half second, so Neon's compute never suspends. Keep an eye on the free tier's compute hours in the Neon console during a long playtest, and stop the server when nobody is playing.
- Same Wi-Fi only? The server is also on `http://<this computer's IP>:8080`.
