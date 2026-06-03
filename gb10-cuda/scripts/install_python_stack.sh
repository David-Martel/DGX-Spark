#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_dirs
require_cmd uv

create_uv_venv() {
  local name="$1"
  local py_spec="$2"
  local venv="$3"
  if [[ ! -d "$venv" ]]; then
    run_logged "create-$name-venv" uv venv --seed --python "$py_spec" "$venv"
  fi
  run_logged "pip-upgrade-$name" uv pip install --python "$venv/bin/python" --upgrade pip setuptools wheel numpy
}

pip_install_best_effort() {
  local name="$1"
  local venv="$2"
  shift 2
  if ! run_logged "pip-$name" uv pip install --python "$venv/bin/python" "$@"; then
    log "$name wheel install had failures; validation report will capture import status"
  fi
}

primary_venv="$GB10_VENVS/media"
compat_venv="$GB10_VENVS/media-cpython-3.13.13"
preview_venv="$GB10_VENVS/media-cpython-3.15.0b1"

create_uv_venv media cpython-3.14.5-linux-aarch64-gnu "$primary_venv"
pip_install_best_effort media-primary "$primary_venv" cupy-cuda13x 'nvidia-nvimgcodec-cu12[all]' pynvvideocodec torch triton

create_uv_venv media-pynv cpython-3.13.13-linux-aarch64-gnu "$compat_venv"
pip_install_best_effort media-pynv "$compat_venv" cupy-cuda13x pynvvideocodec triton

if uv python list | grep -q 'cpython-3.15.0b1-linux-aarch64-gnu'; then
  create_uv_venv media-preview cpython-3.15.0b1-linux-aarch64-gnu "$preview_venv"
  pip_install_best_effort media-preview "$preview_venv" cupy-cuda13x pynvvideocodec
fi

report="$GB10_REPORTS/validate-python-stack-$(timestamp).md"
append_report_header "$report" "GB10 Python GPU Media Stack Validation"
{
  printf '## Environment Matrix\n\n'
  printf -- '- Primary uv media venv: `%s` (Python 3.14 target)\n' "$primary_venv"
  printf -- '- PyNvVideoCodec compatibility venv: `%s` (Python 3.13 target)\n' "$compat_venv"
  printf -- '- Python 3.15 preview venv: `%s` (validated when CUDA wheels exist)\n\n' "$preview_venv"

  validate_venv() {
    local label="$1"
    local venv="$2"
    [[ -x "$venv/bin/python" ]] || return 0
    printf '## %s\n\n```text\n' "$label"
    "$venv/bin/python" - <<'PY'
import sys
print("python", sys.version.replace("\n", " "))
mods = ["cupy", "torch", "triton", "PyNvVideoCodec", "nvidia.nvimgcodec"]
for mod in mods:
    try:
        m = __import__(mod)
        print(mod, "OK", getattr(m, "__version__", ""))
    except Exception as exc:
        print(mod, "FAILED", repr(exc))
try:
    import cupy as cp
    print("cupy devices", cp.cuda.runtime.getDeviceCount())
    a = cp.arange(1024, dtype=cp.float32)
    print("cupy sum", float(a.sum().get()))
except Exception as exc:
    print("cupy smoke failed", repr(exc))
PY
    printf '\n```\n\n'
  }

  validate_venv "Primary Media Venv" "$primary_venv"
  validate_venv "PyNvVideoCodec Compatibility Venv" "$compat_venv"
  validate_venv "Python 3.15 Preview Venv" "$preview_venv"
} >> "$report" 2>&1

mark_done python-stack
log "Python stack validation report: $report"
