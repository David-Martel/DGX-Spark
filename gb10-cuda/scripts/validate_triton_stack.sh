#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_dirs
require_cmd curl

image="${TRITON_SERVER_IMAGE:-nvcr.io/nvidia/tritonserver:25.12-py3}"
name="${TRITON_CONTAINER_NAME:-gb10-triton-smoke}"
http_port="${TRITON_HTTP_PORT:-18000}"
grpc_port="${TRITON_GRPC_PORT:-18001}"
metrics_port="${TRITON_METRICS_PORT:-18002}"
model_repo="$GB10_ROOT/triton/model_repository"
report="$GB10_REPORTS/validate-triton-stack-$(timestamp).md"
append_report_header "$report" "GB10 Triton Stack Validation"

mkdir -p "$model_repo"

cleanup() {
  sudo docker rm -f "$name" >/dev/null 2>&1 || true
  [[ -n "${kernel_smoke:-}" && -f "$kernel_smoke" ]] && rm -f "$kernel_smoke"
  true
}
trap cleanup EXIT

section() {
  printf '\n## %s\n\n```text\n' "$1" >> "$report"
  shift
  "$@" >> "$report" 2>&1
  printf '\n```\n' >> "$report"
}

kernel_smoke="$(mktemp /tmp/gb10_triton_kernel_XXXXXX.py)"
cat > "$kernel_smoke" <<'PY'
import torch
import triton
import triton.language as tl


@triton.jit
def add_kernel(x, y, out, n: tl.constexpr, BLOCK: tl.constexpr):
    pid = tl.program_id(axis=0)
    offsets = pid * BLOCK + tl.arange(0, BLOCK)
    mask = offsets < n
    a = tl.load(x + offsets, mask=mask)
    b = tl.load(y + offsets, mask=mask)
    tl.store(out + offsets, a + b, mask=mask)


n = 1024
x = torch.arange(n, device="cuda", dtype=torch.float32)
y = torch.ones(n, device="cuda", dtype=torch.float32) * 2
out = torch.empty_like(x)
add_kernel[(triton.cdiv(n, 256),)](x, y, out, n, BLOCK=256)
torch.cuda.synchronize()
print("triton", triton.__version__)
print("torch", torch.__version__)
print("cuda_available", torch.cuda.is_available())
print("device", torch.cuda.get_device_name(0))
print("sum", float(out.sum().item()))
PY

section "Python Triton Compiler Kernel Smoke" env LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}" "$GB10_VENVS/media/bin/python" "$kernel_smoke"

section "Triton Server Image" bash -lc "sudo docker image inspect '$image' --format 'id={{.Id}} repoDigests={{json .RepoDigests}} size={{.Size}}' || sudo docker pull '$image'"

cleanup
{
  printf '\n## Triton Server Smoke\n\n```text\n'
  sudo docker run -d --rm --gpus all --name "$name" \
    -p "$http_port:8000" -p "$grpc_port:8001" -p "$metrics_port:8002" \
    -v "$model_repo:/models" \
    "$image" tritonserver --model-repository=/models --model-control-mode=explicit
  for i in $(seq 1 60); do
    if curl -fsS "http://127.0.0.1:$http_port/v2/health/ready" >/dev/null; then
      echo "ready"
      break
    fi
    sleep 1
    if ! sudo docker ps --format '{{.Names}}' | grep -q "^$name$"; then
      echo "container exited"
      sudo docker logs "$name" 2>&1 | tail -120 || true
      exit 1
    fi
    if [[ "$i" == 60 ]]; then
      echo "timeout"
      sudo docker logs "$name" 2>&1 | tail -120 || true
      exit 1
    fi
  done
  curl -fsS "http://127.0.0.1:$http_port/v2"
  echo
  sudo docker logs "$name" 2>&1 | tail -100
  printf '\n```\n'
} >> "$report" 2>&1

cleanup
mark_done triton-validated
log "Triton validation report: $report"
