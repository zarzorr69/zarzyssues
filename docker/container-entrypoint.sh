#!/bin/sh
set -eu
# Only these two newly introduced named-volume roots need extra ownership setup.
mkdir -p /app/.agents /app/.config
chown "${PUID:-999}:${PGID:-1000}" /app/.agents /app/.config
exec /usr/local/bin/entrypoint.sh "$@"
