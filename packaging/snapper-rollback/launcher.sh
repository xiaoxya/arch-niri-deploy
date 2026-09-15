#!/usr/bin/env bash
set -Eeuo pipefail
# This project deliberately uses one guarded backend for both command names.
exec /usr/lib/snapper-rollback/scripts/rollback-snapshot.sh "$@"
