#!/bin/sh
# Backups off the machine (ops/production/docker-compose.yml, profile
# offsite): an hour after the nightly backup (BACKUP_HOUR + 1, UTC), the
# dumps in /backups are copied to S3-compatible storage, for example a
# Cloudflare R2 bucket, so they survive losing this machine. Copies older
# than OFFSITE_KEEP_DAYS (default 30) are deleted there. OFFSITE_ONCE=1
# copies at once and stops (by hand:
#   docker compose run --rm -e OFFSITE_ONCE=1 offsite).
#
# .env: OFFSITE_ENDPOINT (R2: https://<account id>.r2.cloudflarestorage.com),
# OFFSITE_BUCKET, OFFSITE_ACCESS_KEY_ID, OFFSITE_SECRET_ACCESS_KEY; optional
# OFFSITE_PROVIDER (default Cloudflare; Other for any S3-compatible store)
# and OFFSITE_PREFIX (default slavian).
#
# Restore from there: rclone copy the dump back into ./backups, then
# pg_restore it as docs/production.md shows.
set -u
for var in OFFSITE_ENDPOINT OFFSITE_BUCKET OFFSITE_ACCESS_KEY_ID OFFSITE_SECRET_ACCESS_KEY; do
  eval "value=\${$var:-}"
  if [ -z "$value" ]; then
    echo "offsite: set $var in .env" >&2
    exit 2
  fi
done

# rclone reads the remote "offsite" from these.
export RCLONE_CONFIG_OFFSITE_TYPE=s3
export RCLONE_CONFIG_OFFSITE_PROVIDER="${OFFSITE_PROVIDER:-Cloudflare}"
export RCLONE_CONFIG_OFFSITE_ENDPOINT="$OFFSITE_ENDPOINT"
export RCLONE_CONFIG_OFFSITE_ACCESS_KEY_ID="$OFFSITE_ACCESS_KEY_ID"
export RCLONE_CONFIG_OFFSITE_SECRET_ACCESS_KEY="$OFFSITE_SECRET_ACCESS_KEY"
export RCLONE_CONFIG_OFFSITE_NO_CHECK_BUCKET=true

target="offsite:$OFFSITE_BUCKET/${OFFSITE_PREFIX:-slavian}"
hour=$(( (${BACKUP_HOUR:-3} + 1) % 24 ))
keep="${OFFSITE_KEEP_DAYS:-30}"

alert() {
  echo "$1" >&2
  [ -n "${ALERT_WEBHOOK_URL:-}" ] || return 0
  body="{\"content\":\"[slavian] $1\",\"text\":\"[slavian] $1\"}"
  wget -q -O /dev/null --header='content-type: application/json' --post-data="$body" "$ALERT_WEBHOOK_URL" || true
}

while true; do
  if [ "${OFFSITE_ONCE:-0}" != 1 ]; then
    now=$(date -u +%s)
    today=$(date -u +%Y-%m-%d)
    next=$(date -u -d "$today $hour:00:00" +%s 2>/dev/null || date -u -D '%Y-%m-%d %H:%M:%S' -d "$today $hour:00:00" +%s)
    [ "$next" -le "$now" ] && next=$((next + 86400))
    sleep $((next - now))
  fi
  status=0
  if rclone copy /backups "$target" --include 'slavian-*.dump' --no-traverse; then
    echo "Copied the backups to $target"
    rclone delete "$target" --include 'slavian-*.dump' --min-age "${keep}d" || true
  else
    status=1
    alert "Copying the database backups off the machine failed."
  fi
  [ "${OFFSITE_ONCE:-0}" = 1 ] && exit "$status"
done
