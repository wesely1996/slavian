#!/usr/bin/env bash
# Moves the game's database from a hosted Postgres (Neon) onto this machine
# (docs/production.md, "Moving the database here"). Run it once, on the
# server, in this directory:
#   ./move-db.sh
#
# What it does, stopping at the first thing that goes wrong:
#  1. reads the hosted database's Postgres version and pins the same one here
#     (POSTGRES_VERSION), and makes POSTGRES_PASSWORD if .env has none;
#  2. stops the game server (players see it down for a few minutes) and
#     counts every table's rows in the hosted database;
#  3. backs it up (the nightly backup's own tool, into ./backups);
#  4. starts Postgres here, checks it is empty, and restores the backup;
#  5. counts the rows again here: they must all match;
#  6. points .env at the local database (DATABASE_URL, COMPOSE_PROFILES
#     with local-db), keeping the old file as .env.before-move;
#  7. starts the server and waits for it to be healthy.
# If the counts differ or the server doesn't come up, .env is put back and
# the server runs on the hosted database again. The hosted database is
# never changed: delete it yourself once the move has proven itself.
set -euo pipefail

main() {
	local here
	here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
	cd "$here"
	[[ -f .env ]] || fail "no .env here"

	# Not while a release deploys.
	exec 9>/tmp/slavian-deploy.lock
	flock -w 600 9

	local old_url
	old_url=$(env_value DATABASE_URL)
	[[ -n "$old_url" ]] || fail "DATABASE_URL is not set in .env"
	[[ "$old_url" != *"@postgres:"* ]] || fail "DATABASE_URL already points at the database on this machine"

	# 1. The same major version here as there, and a password.
	local version
	version=$(docker run --rm postgres:17 psql "$old_url" -tAc 'SHOW server_version_num') || fail "can't reach the database at DATABASE_URL"
	version=$((version / 10000))
	(( version >= 14 )) || fail "the hosted database runs Postgres $version; 14 or newer is needed"
	echo "The hosted database runs Postgres $version"
	cp .env .env.before-move
	set_env POSTGRES_VERSION "$version"
	local password
	password=$(env_value POSTGRES_PASSWORD)
	if [[ -z "$password" || "$password" == change-me ]]; then
		password=$(openssl rand -hex 24)
		set_env POSTGRES_PASSWORD "$password"
	fi

	# 2. Nothing changes the hosted database from here on.
	echo "Stopping the game server"
	docker compose stop server
	local before
	before=$(docker run --rm "postgres:$version" psql "$old_url" -tAc "$(row_counts)") || restore_env_and_fail "can't count the hosted database's rows"

	# 3. A backup, as the nightly one makes it.
	echo "Backing up the hosted database"
	docker compose run --rm -e BACKUP_ONCE=1 backup || restore_env_and_fail "the backup failed"
	local dump
	dump=$(ls -t backups/slavian-*.dump | head -n 1)
	echo "Backed up to $dump"

	# 4. Postgres here, empty, with the backup restored into it.
	echo "Starting Postgres $version here"
	COMPOSE_PROFILES=local-db docker compose up -d postgres
	wait_healthy postgres || restore_env_and_fail "Postgres here didn't start"
	local tables
	tables=$(local_psql "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'")
	[[ "$tables" == 0 ]] || restore_env_and_fail "the database here isn't empty ($tables tables): remove its volume first (docker compose down; docker volume rm slavian_pgdata) if nothing in it is needed"
	echo "Restoring $dump"
	# Ownership and grants belong to the hosted database's roles: here the
	# slavian user owns everything. Errors are checked by the counts below.
	docker compose exec -T postgres pg_restore --no-owner --no-privileges -U slavian -d slavian < "$dump" || echo "pg_restore reported problems; checking the rows" >&2

	# 5. Every table, every row.
	local after
	after=$(local_psql "$(row_counts)")
	if [[ "$before" != "$after" ]]; then
		diff <(echo "$before") <(echo "$after") >&2 || true
		restore_env_and_fail "the rows here don't match the hosted database"
	fi
	echo "All $(echo "$after" | wc -l) tables match, row for row"

	# 6. The server's database is this one now; the old address is kept.
	set_env DATABASE_URL "postgres://slavian:$password@postgres:5432/slavian"
	set_env HOSTED_DATABASE_URL "$old_url"
	local profiles
	profiles=$(env_value COMPOSE_PROFILES)
	[[ ",$profiles," == *,local-db,* ]] || set_env COMPOSE_PROFILES "${profiles:+$profiles,}local-db"

	# 7. Up again, on the database here.
	echo "Starting the game server"
	docker compose up -d
	if ! wait_healthy server; then
		docker compose logs --tail 60 server >&2 || true
		restore_env_and_fail "the server didn't come up healthy on the database here"
	fi
	echo
	echo "Done: the game runs on Postgres here. The hosted database is untouched;"
	echo "keep it a week, then delete it. Going back to it: docs/production.md."
}

# Every table in public with its row count, one "table|count" a line.
row_counts() {
	cat <<'SQL'
SELECT table_name || '|' || (xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM %I.%I', table_schema, table_name), false, true, '')))[1]::text
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
ORDER BY table_name
SQL
}

local_psql() {
	docker compose exec -T postgres psql -U slavian -d slavian -tAc "$1"
}

# A value from .env ("" when unset).
env_value() {
	sed -n "s/^$1=//p" .env | tail -n 1
}

# Sets KEY=value in .env, whatever characters the value holds.
set_env() {
	local tmp
	tmp=$(mktemp)
	grep -v "^$1=" .env > "$tmp" || true
	printf '%s=%s\n' "$1" "$2" >> "$tmp"
	cat "$tmp" > .env
	rm -f "$tmp"
}

# Healthy within two minutes (Docker's health check).
wait_healthy() {
	local container state
	for _ in $(seq 1 24); do
		container=$(docker compose ps -q "$1")
		state=$(docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null || true)
		[[ "$state" == healthy ]] && return 0
		sleep 5
	done
	return 1
}

fail() {
	echo "move-db: $1" >&2
	exit 1
}

# Back to the hosted database: the old .env, and the server on it.
restore_env_and_fail() {
	echo "move-db: $1" >&2
	cp .env.before-move .env
	echo "Starting the game server again on the hosted database" >&2
	docker compose up -d server || true
	exit 1
}

main "$@"
