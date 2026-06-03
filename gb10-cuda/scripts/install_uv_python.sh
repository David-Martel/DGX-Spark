#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_dirs
report="$GB10_REPORTS/uv-python-$(timestamp).md"
append_report_header "$report" "GB10 uv Python Setup"

if ! command -v uv >/dev/null 2>&1; then
  log "uv not found; installing official standalone uv"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi

require_cmd uv

{
  printf '## uv Version\n\n```text\n'
  uv --version
  printf '\n```\n\n## Available 3.15/3.14 Builds\n\n```text\n'
  uv python list --all-versions | grep -E 'cpython-3\.(15|14)' | head -80
  printf '\n```\n'
} >> "$report" 2>&1

log "installing uv-managed Python 3.15 beta default"
if uv python install --default cpython-3.15.0b1-linux-aarch64-gnu >> "$report" 2>&1; then
  mark_done uv-python-315
else
  log "Python 3.15 beta install failed; report captures details"
fi

log "installing uv-managed Python 3.14 stable fallback"
uv python install cpython-3.14.5-linux-aarch64-gnu >> "$report" 2>&1
mark_done uv-python-314

venv="$GB10_VENVS/py315-smoke"
rm -rf "$venv"
uv venv --python cpython-3.15.0b1-linux-aarch64-gnu "$venv" >> "$report" 2>&1 || uv venv --python cpython-3.14.5-linux-aarch64-gnu "$venv" >> "$report" 2>&1
"$venv/bin/python" --version >> "$report" 2>&1

{
  printf '\n## PATH Guidance\n\n```text\n'
  printf 'prepend %s/.local/bin for uv default python shims\n' "$HOME"
  command -v python || true
  python --version 2>&1 || true
  command -v python3 || true
  python3 --version 2>&1 || true
  printf '\n```\n'
} >> "$report"

mark_done uv-python
log "uv Python report: $report"
