#!/bin/sh
set -eu

if [ "$(id -u)" = "0" ]; then
  # Existing releases wrote bind-mounted data as root. Repair only the known
  # ledger paths before dropping privileges so upgrades remain compatible.
  install -d -o ledger -g ledger /data /data/uploads /data/backups
  for item in \
    /data/ledger.db \
    /data/ledger.db-shm \
    /data/ledger.db-wal \
    /data/config.yaml \
    /data/uploads \
    /data/backups; do
    if [ -e "$item" ]; then
      chown -R ledger:ledger "$item"
    fi
  done
  exec su-exec ledger:ledger "$@"
fi

exec "$@"
