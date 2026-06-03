#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

if [[ "${ALLOW_PURGE_GB10_CUDA:-0}" != "1" ]]; then
  die "set ALLOW_PURGE_GB10_CUDA=1 to remove $GB10_ROOT"
fi

sudo rm -rf "$GB10_ROOT"
log "removed $GB10_ROOT"
