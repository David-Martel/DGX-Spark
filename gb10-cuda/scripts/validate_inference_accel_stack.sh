#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/accel_stack_common.sh"

ensure_dirs

strict=0
for arg in "$@"; do
  case "$arg" in
    --strict) strict=1 ;;
    --help|-h)
      cat <<'EOF'
Usage: gb10-cuda/scripts/validate_inference_accel_stack.sh [--strict]

Validates the DGX Spark inference acceleration venv and emits Markdown plus JSON
reports for CUDA, ONNX, TensorRT, Torch-TensorRT, and FlashAttention readiness.
EOF
      exit 0
      ;;
    *) die "unknown argument: $arg" ;;
  esac
done

inference_venv="${GB10_INFERENCE_VENV:-$GB10_VENVS/inference-cpython-3.13.13}"
python_exe="$inference_venv/bin/python"
[[ -x "$python_exe" ]] || die "missing inference venv python: $python_exe; run just install-inference-accel-stack"

report="$GB10_REPORTS/validate-inference-accel-stack-$(timestamp).md"
json_report="${report%.md}.json"
append_report_header "$report" "GB10 Inference Acceleration Validation"

gb10_accel_export_env
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}"
export GB10_ACCEL_STRICT="$strict"
export GB10_ACCEL_JSON_REPORT="$json_report"

{
  printf '## Python Validation\n\n```json\n'
  "$python_exe" - <<'PY'
from __future__ import annotations

import importlib
import json
import os
import platform
import sys
import tempfile
from pathlib import Path
from typing import Any


def module_status(name: str) -> dict[str, Any]:
    try:
        module = importlib.import_module(name)
    except Exception as exc:
        return {"available": False, "error": repr(exc)}
    return {"available": True, "version": str(getattr(module, "__version__", "unknown"))}


def torch_status() -> dict[str, Any]:
    status = module_status("torch")
    if not status["available"]:
        return status
    import torch

    status.update(
        {
            "cuda_available": bool(torch.cuda.is_available()),
            "torch_cuda_version": getattr(torch.version, "cuda", None),
            "compile_available": hasattr(torch, "compile"),
            "float32_matmul_precision": getattr(
                torch, "get_float32_matmul_precision", lambda: None
            )(),
        }
    )
    if torch.cuda.is_available():
        props = torch.cuda.get_device_properties(0)
        status["device"] = {
            "name": props.name,
            "compute_capability": f"{props.major}.{props.minor}",
            "total_memory_gib": round(props.total_memory / (1024**3), 3),
            "multi_processor_count": props.multi_processor_count,
            "bf16_supported": bool(getattr(torch.cuda, "is_bf16_supported", lambda: False)()),
        }
        x = torch.arange(1024, device="cuda", dtype=torch.float32)
        status["cuda_smoke_sum"] = float((x + 1).sum().item())
    return status


def onnx_export_status() -> dict[str, Any]:
    imports = {name: module_status(name) for name in ["torch", "onnx", "onnxscript"]}
    if not all(value["available"] for value in imports.values()):
        return {"ok": False, "imports": imports}
    import onnx
    import torch

    class Tiny(torch.nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.linear = torch.nn.Linear(4, 3)

        def forward(self, value: torch.Tensor) -> torch.Tensor:
            return torch.relu(self.linear(value))

    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "tiny.onnx"
        model = Tiny().eval()
        sample = torch.randn(1, 4)
        try:
            torch.onnx.export(
                model,
                sample,
                path,
                input_names=["input"],
                output_names=["output"],
                opset_version=18,
                dynamo=True,
            )
        except TypeError:
            torch.onnx.export(
                model,
                sample,
                path,
                input_names=["input"],
                output_names=["output"],
                opset_version=18,
            )
        exported = onnx.load(path)
        onnx.checker.check_model(exported)
        return {"ok": True, "bytes": path.stat().st_size, "ir_version": exported.ir_version}


def tensorrt_status(onnx_ok: bool) -> dict[str, Any]:
    status = module_status("tensorrt")
    if not status["available"]:
        return status
    try:
        import tensorrt as trt

        logger = trt.Logger(trt.Logger.WARNING)
        builder = trt.Builder(logger)
        status["builder_created"] = bool(builder)
        status["onnx_parser_available"] = hasattr(trt, "OnnxParser")
        status["onnx_export_ready"] = bool(onnx_ok)
    except Exception as exc:
        status["builder_error"] = repr(exc)
    return status


def flash_attn_status() -> dict[str, Any]:
    status = module_status("flash_attn")
    if not status["available"]:
        return status
    try:
        import torch
        from flash_attn import flash_attn_func

        if torch.cuda.is_available():
            dtype = torch.bfloat16 if torch.cuda.is_bf16_supported() else torch.float16
            q = torch.randn(1, 16, 4, 32, device="cuda", dtype=dtype)
            k = torch.randn_like(q)
            v = torch.randn_like(q)
            out = flash_attn_func(q, k, v, dropout_p=0.0, causal=False)
            torch.cuda.synchronize()
            status["smoke"] = {
                "shape": list(out.shape),
                "dtype": str(out.dtype),
                "finite": bool(torch.isfinite(out).all().item()),
            }
    except Exception as exc:
        status["smoke_error"] = repr(exc)
    return status


onnx_export = onnx_export_status()
result = {
    "ok": True,
    "python": {
        "version": sys.version.split()[0],
        "executable": sys.executable,
        "platform": platform.platform(),
        "machine": platform.machine(),
    },
    "environment": {
        "CUDA_HOME": os.environ.get("CUDA_HOME"),
        "TORCH_CUDA_ARCH_LIST": os.environ.get("TORCH_CUDA_ARCH_LIST"),
        "TRITON_PTXAS_PATH": os.environ.get("TRITON_PTXAS_PATH"),
    },
    "modules": {
        "torch": torch_status(),
        "triton": module_status("triton"),
        "cuda_bindings": module_status("cuda.bindings"),
        "flashinfer": module_status("flashinfer"),
        "onnx": module_status("onnx"),
        "onnxscript": module_status("onnxscript"),
        "tensorrt": tensorrt_status(bool(onnx_export.get("ok"))),
        "torch_tensorrt": module_status("torch_tensorrt"),
        "flash_attn": flash_attn_status(),
    },
    "onnx_export": onnx_export,
}
required = ["torch", "onnx", "onnxscript", "tensorrt"]
missing = [
    name for name in required if not result["modules"].get(name, {}).get("available")
]
if not result["modules"]["torch"].get("cuda_available"):
    missing.append("torch.cuda")
result["required_missing"] = missing
result["ok"] = not missing

json_text = json.dumps(result, indent=2, sort_keys=True)
print(json_text)
json_report = os.environ.get("GB10_ACCEL_JSON_REPORT")
if json_report:
    Path(json_report).write_text(json_text + "\n", encoding="utf-8")
if os.environ.get("GB10_ACCEL_STRICT") == "1" and missing:
    raise SystemExit(1)
PY
  printf '\n```\n'
} >> "$report" 2>&1

if [[ "$strict" -eq 1 ]]; then
  "$python_exe" - "$json_report" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if not data.get("ok"):
    print("strict validation failed:", ", ".join(data.get("required_missing", [])))
    raise SystemExit(1)
PY
fi

mark_done inference-accel-validated
log "Inference acceleration validation report: $report"
log "Inference acceleration JSON report: $json_report"
