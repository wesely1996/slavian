#!/usr/bin/env bash
# Deploys a release on this machine: the repository's files at the tag, and
# the server image CI published for it (ghcr.io/<owner>/slavian-server:<tag>).
# release.yml runs it over SSH after every v* tag; by hand:
#   /opt/slavian/ops/production/deploy.sh v0.2.0
#
# The release workflow's SSH key may run nothing else: authorized_keys gives
# it `command="/opt/slavian/ops/production/deploy.sh",restrict`, so the tag
# arrives in SSH_ORIGINAL_COMMAND and is checked before anything happens.
# If the new server doesn't come up healthy, the previous image runs again
# and the deploy fails. (Database migrations are not undone.)
set -euo pipefail

# Everything is in main(): bash reads a script as it runs, and checking out
# the tag below may replace this very file.
main() {
	local tag="${1:-${SSH_ORIGINAL_COMMAND:-}}"
	if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		echo "usage: deploy.sh vX.Y.Z (got '${tag}')" >&2
		exit 2
	fi
	local here repo
	here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
	repo=$(cd "$here/../.." && pwd)
	cd "$here"

	# One deploy at a time.
	exec 9>/tmp/slavian-deploy.lock
	flock -w 600 9

	local previous
	previous=$(sed -n 's/^SLAVIAN_TAG=//p' .env)
	echo "Deploying $tag (running: ${previous:-main})"
	git -C "$repo" fetch -q --tags --force origin
	git -C "$repo" -c advice.detachedHead=false checkout -q "refs/tags/$tag"

	set_tag "$tag"
	docker compose pull -q server
	docker compose up -d --remove-orphans
	if healthy; then
		echo "Deployed $tag"
		docker image prune -f >/dev/null
		return 0
	fi

	echo "The server didn't come up healthy on $tag; going back to ${previous:-main}" >&2
	docker compose logs --tail 60 server >&2 || true
	set_tag "${previous:-main}"
	docker compose up -d
	exit 1
}

# Pins the image tag the compose file runs (SLAVIAN_TAG in .env).
set_tag() {
	if grep -q '^SLAVIAN_TAG=' .env; then
		sed -i "s/^SLAVIAN_TAG=.*/SLAVIAN_TAG=$1/" .env
	else
		echo "SLAVIAN_TAG=$1" >> .env
	fi
}

# Healthy within two minutes: Docker's health check, then /health over HTTPS.
healthy() {
	local domain container state
	domain=$(sed -n 's/^DOMAIN=//p' .env)
	container=$(docker compose ps -q server)
	for _ in $(seq 1 24); do
		state=$(docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null || true)
		if [[ "$state" == healthy ]] && curl -fsS -m 10 "https://$domain/health" >/dev/null; then
			return 0
		fi
		sleep 5
	done
	return 1
}

main "$@"
