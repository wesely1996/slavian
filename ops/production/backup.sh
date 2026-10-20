#!/bin/sh
# Nightly database backup (ops/production/docker-compose.yml): a custom-format
# pg_dump of DATABASE_URL into /backups at BACKUP_HOUR (UTC, default 3), the
# last BACKUP_KEEP_DAYS (default 14) kept. BACKUP_ONCE=1 backs up at once and
# stops (a backup by hand: docker compose run --rm -e BACKUP_ONCE=1 backup).
# Restore with
#   pg_restore --clean --if-exists -d "$DATABASE_URL" backups/<file>.dump
set -u
dir="${BACKUP_DIR:-/backups}"
hour="${BACKUP_HOUR:-3}"
keep="${BACKUP_KEEP_DAYS:-14}"
while true; do
  if [ "${BACKUP_ONCE:-0}" != 1 ]; then
    now=$(date -u +%s)
    next=$(date -u -d "$(date -u +%Y-%m-%d) ${hour}:00" +%s)
    [ "$next" -le "$now" ] && next=$((next + 86400))
    sleep $((next - now))
  fi
  file="$dir/slavian-$(date -u +%Y%m%d-%H%M).dump"
  status=0
  if pg_dump --format=custom --no-owner --file="$file.part" "$DATABASE_URL"; then
    mv "$file.part" "$file"
    echo "Backed up to $file"
  else
    status=1
    rm -f "$file.part"
    echo "Backup failed" >&2
    body='{"content":"[slavian] The nightly database backup failed.","text":"[slavian] The nightly database backup failed."}'
    if [ -n "${ALERT_WEBHOOK_URL:-}" ]; then
      if command -v curl >/dev/null; then
        curl -fsS -H 'content-type: application/json' -d "$body" "$ALERT_WEBHOOK_URL" >/dev/null || true
      elif command -v wget >/dev/null; then
        wget -q -O /dev/null --header='content-type: application/json' --post-data="$body" "$ALERT_WEBHOOK_URL" || true
      fi
    fi
  fi
  find "$dir" -name 'slavian-*.dump' -mtime +"$keep" -delete
  [ "${BACKUP_ONCE:-0}" = 1 ] && exit "$status"
done
