#!/usr/bin/env bash
# Keeps this machine's own software up to date (docs/production.md, "The
# machine's updates"): Ubuntu installs security updates every day, and when
# one needs a restart, the machine reboots at 03:00 local time. Run it once,
# as root, in this directory:
#   ./night-reboots.sh                    (Europe/Belgrade, 03:00)
#   ./night-reboots.sh Europe/Berlin 04:00
# Running it again changes nothing that is already set.
set -euo pipefail

zone="${1:-Europe/Belgrade}"
at="${2:-03:00}"

[[ $EUID -eq 0 ]] || { echo "night-reboots: run it as root" >&2; exit 1; }
[[ "$at" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || { echo "night-reboots: the time is HH:MM, got '$at'" >&2; exit 2; }

timedatectl set-timezone "$zone"
if ! command -v unattended-upgrade >/dev/null; then
	apt-get update
	apt-get install -y unattended-upgrades
fi

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
cat > /etc/apt/apt.conf.d/52slavian-reboot <<EOF
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "$at";
EOF

echo "Time zone: $(timedatectl show -p Timezone --value), now $(date '+%H:%M')"
apt-config dump | grep -E 'APT::Periodic::(Update-Package-Lists|Unattended-Upgrade) |Unattended-Upgrade::Automatic-Reboot'
if [[ -f /var/run/reboot-required ]]; then
	echo "A restart is waiting now: it happens at $at after the next daily update, or run 'reboot' yourself."
fi
