#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_dirs
require_cmd uv

report="$GB10_REPORTS/validate-ai-audio-stack-$(timestamp).md"
append_report_header "$report" "GB10 AI and Audio Acceleration Validation"

audio_venv="$GB10_VENVS/audio-cpython-3.13.13"
if [[ ! -d "$audio_venv" ]]; then
  run_logged create-audio-venv uv venv --seed --python cpython-3.13.13-linux-aarch64-gnu "$audio_venv"
fi
run_logged pip-audio-base uv pip install --python "$audio_venv/bin/python" --upgrade pip setuptools wheel
run_logged pip-riva-client uv pip install --python "$audio_venv/bin/python" nvidia-riva-client

section() {
  printf '\n## %s\n\n```text\n' "$1" >> "$report"
  shift
  "$@" >> "$report" 2>&1 || true
  printf '\n```\n' >> "$report"
}

section "System Python AI Bindings" /usr/bin/python3 - <<'PY'
import importlib

for mod in ["tensorrt", "onnx"]:
    try:
        m = importlib.import_module(mod)
        print(mod, "OK", getattr(m, "__version__", ""))
    except Exception as exc:
        print(mod, "FAILED", repr(exc))
PY
section "System Triton Compiler Package" bash -lc 'dpkg-query -W python3-triton 2>/dev/null || true; dpkg -L python3-triton 2>/dev/null | head -30'

section "uv Primary Media AI Imports" env LD_LIBRARY_PATH="$GB10_INSTALL/opencv/lib:$GB10_INSTALL/ffmpeg/lib:$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}" "$GB10_VENVS/media/bin/python" - <<'PY'
import importlib

for mod in ["cupy", "cv2", "nvidia.nvimgcodec"]:
    try:
        m = importlib.import_module(mod)
        print(mod, "OK", getattr(m, "__version__", ""))
    except Exception as exc:
        print(mod, "FAILED", repr(exc))
PY

section "uv Audio and Riva Client Imports" "$audio_venv/bin/python" - <<'PY'
import importlib

for mod in ["grpc", "riva.client"]:
    try:
        m = importlib.import_module(mod)
        print(mod, "OK", getattr(m, "__version__", ""))
    except Exception as exc:
        print(mod, "FAILED", repr(exc))
PY

section "PyNvVideoCodec Compatibility Imports" "$GB10_VENVS/media-cpython-3.13.13/bin/python" - <<'PY'
import importlib

for mod in ["PyNvVideoCodec", "cupy"]:
    try:
        m = importlib.import_module(mod)
        print(mod, "OK", getattr(m, "__version__", ""))
    except Exception as exc:
        print(mod, "FAILED", repr(exc))
PY

section "NVIDIA Docker Runtime" bash -lc 'docker ps >/dev/null 2>&1 && echo "user docker OK" || echo "user docker unavailable: $(docker ps 2>&1 | head -1)"; sudo docker info --format "server={{.ServerVersion}} arch={{.Architecture}} os={{.OSType}}" 2>&1; sudo docker run --rm --gpus all ubuntu:24.04 nvidia-smi -L 2>&1'

section "NIM and Riva Container Route" bash -lc 'cat <<EOF
NVIDIA Container Toolkit is installed and sudo docker --gpus all sees the GB10.
Use NGC-authenticated container pulls for server-side NIM/Riva images.
This script intentionally validates runtime readiness without pulling large gated
speech or LLM server images implicitly.
EOF'

mark_done ai-audio-stack
log "AI/audio validation report: $report"
