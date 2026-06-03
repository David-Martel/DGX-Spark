#!/usr/bin/env bash
set -Eeuo pipefail

export GB10_HOME="${GB10_HOME:-$HOME/gb10-cuda}"
export GB10_ROOT="${GB10_ROOT:-/opt/gb10-cuda}"
export GB10_SRC="$GB10_ROOT/src"
export GB10_BUILD="$GB10_ROOT/build"
export GB10_INSTALL="$GB10_ROOT/install"
export GB10_STATE="$GB10_ROOT/state"
export GB10_LOGS="$GB10_ROOT/logs"
export GB10_VENVS="$GB10_ROOT/venvs"
export GB10_REPORTS="$GB10_HOME/reports"
export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
export CUDA_ARCH_BIN="${CUDA_ARCH_BIN:-12.1}"
export MAKE_JOBS="${MAKE_JOBS:-$(nproc)}"

timestamp() {
  date -u +"%Y%m%dT%H%M%SZ"
}

log() {
  printf '[%s] %s\n' "$(date -Is)" "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

ensure_dirs() {
  mkdir -p "$GB10_REPORTS"
  sudo mkdir -p "$GB10_SRC" "$GB10_BUILD" "$GB10_INSTALL" "$GB10_STATE" "$GB10_LOGS" "$GB10_VENVS"
  sudo chown -R "$USER:$USER" "$GB10_ROOT"
}

run_logged() {
  local name="$1"
  shift
  ensure_dirs
  local logfile="$GB10_LOGS/${name}-$(timestamp).log"
  log "running: $*"
  log "log: $logfile"
  "$@" 2>&1 | tee "$logfile"
}

mark_done() {
  local marker="$1"
  ensure_dirs
  touch "$GB10_STATE/$marker.done"
}

is_done() {
  local marker="$1"
  [[ -f "$GB10_STATE/$marker.done" && "${FORCE_REBUILD:-0}" != "1" ]]
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

append_report_header() {
  local report="$1"
  local title="$2"
  {
    printf '# %s\n\n' "$title"
    printf '%s\n' "- Generated: \`$(date -Is)\`"
    printf '%s\n' "- Host: \`$(hostname)\`"
    printf '%s\n\n' "- User: \`$USER\`"
  } > "$report"
}
