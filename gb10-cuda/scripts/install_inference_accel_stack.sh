#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/accel_stack_common.sh"

ensure_dirs
require_cmd uv

strict=0
skip_flash_attn=0
skip_torch_tensorrt=0

for arg in "$@"; do
  case "$arg" in
    --strict) strict=1 ;;
    --skip-flash-attn) skip_flash_attn=1 ;;
    --skip-torch-tensorrt) skip_torch_tensorrt=1 ;;
    --help|-h)
      cat <<'EOF'
Usage: gb10-cuda/scripts/install_inference_accel_stack.sh [--strict] [--skip-flash-attn] [--skip-torch-tensorrt]

Creates the DGX Spark inference acceleration venv and installs CUDA 13 oriented
Python tooling for ONNX, ONNXScript, TensorRT, Torch-TensorRT, and FlashAttention.

Environment:
  GB10_INFERENCE_PYTHON       uv Python spec, default cpython-3.13.13-linux-aarch64-gnu
  GB10_INFERENCE_VENV         target venv, default /opt/gb10-cuda/venvs/inference-cpython-3.13.13
  GB10_TORCH_VERSION_SPEC     Torch version glob, default 2.12.*
  GB10_TENSORRT_VERSION_SPEC  TensorRT version range, default >=11,<12
EOF
      exit 0
      ;;
    *) die "unknown argument: $arg" ;;
  esac
done

python_spec="$GB10_INFERENCE_PYTHON"
inference_venv="${GB10_INFERENCE_VENV:-$GB10_VENVS/inference-cpython-3.13.13}"
report="$GB10_REPORTS/install-inference-accel-stack-$(timestamp).md"
append_report_header "$report" "GB10 Inference Acceleration Install"

gb10_accel_export_env

if [[ ! -d "$inference_venv" ]]; then
  run_logged create-inference-venv uv venv --seed --python "$python_spec" "$inference_venv"
fi

pip_install() {
  local name="$1"
  shift
  run_logged "pip-inference-$name" uv pip install --python "$inference_venv/bin/python" "$@"
}

pip_install_best_effort() {
  local name="$1"
  shift
  if ! pip_install "$name" "$@"; then
    log "$name install failed; validation will record import status"
    return 0
  fi
}

{
  printf '## Target\n\n'
  printf -- '- Python spec: `%s`\n' "$python_spec"
  printf -- '- Venv: `%s`\n' "$inference_venv"
  printf -- '- CUDA_HOME: `%s`\n' "$CUDA_HOME"
  printf -- '- TORCH_CUDA_ARCH_LIST: `%s`\n' "$TORCH_CUDA_ARCH_LIST"
  printf -- '- TRITON_PTXAS_PATH: `%s`\n' "$TRITON_PTXAS_PATH"
  printf -- '- FlashAttention MAX_JOBS/NVCC_THREADS: `%s` / `%s`\n\n' "$MAX_JOBS" "$NVCC_THREADS"
  printf '## Package Policy\n\n```text\n'
  gb10_accel_print_policy
  printf '\n```\n\n'
} >> "$report"

pip_install base --upgrade pip setuptools wheel
mapfile -t core_packages < <(gb10_accel_core_packages)
pip_install core "${core_packages[@]}"
mapfile -t tensorrt_packages < <(gb10_accel_tensorrt_packages)
pip_install_best_effort tensorrt "${tensorrt_packages[@]}"

if [[ "$skip_torch_tensorrt" -eq 0 ]]; then
  log "Torch-TensorRT is not installed into the TensorRT 11 lane by default; use a separate compatibility venv with TensorRT $GB10_TORCH_TENSORRT_TENSORRT_VERSION_SPEC if needed"
fi

if [[ "$skip_flash_attn" -eq 0 ]]; then
  if ! run_logged pip-inference-flash-attn \
    env MAX_JOBS="$MAX_JOBS" NVCC_THREADS="$NVCC_THREADS" CUDA_HOME="$CUDA_HOME" TORCH_CUDA_ARCH_LIST="$TORCH_CUDA_ARCH_LIST" \
    uv pip install --python "$inference_venv/bin/python" --no-build-isolation flash-attn; then
    log "flash-attn install failed; validation will record import status"
  fi
fi

validate_args=()
[[ "$strict" -eq 1 ]] && validate_args+=(--strict)
"$SCRIPT_DIR/validate_inference_accel_stack.sh" "${validate_args[@]}"
mark_done inference-accel-stack
log "Inference acceleration install report: $report"
