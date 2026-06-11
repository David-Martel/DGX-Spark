#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/accel_stack_common.sh"

ensure_dirs
gb10_accel_export_env

report="$GB10_REPORTS/audit-torch-envs-$(timestamp).md"
json_report="${report%.md}.json"
append_report_header "$report" "GB10 Torch Environment Audit"

entries=(
  "dgx-inference:$GB10_VENVS/inference-cpython-3.13.13:2.12:TensorRT/SAM3 acceleration"
  "dgx-media:$GB10_VENVS/media:2.12:OpenCV/CuPy/Triton media"
  "dgx-media-pynv:$GB10_VENVS/media-cpython-3.13.13:any:PyNvVideoCodec compatibility"
)

maybe_add_repo_venv() {
  local label="$1"
  local repo="$2"
  local venv="$3"
  local expected="$4"
  local purpose="$5"
  [[ -x "$repo/$venv/bin/python" ]] || return 0
  entries+=("$label:$repo/$venv:$expected:$purpose")
}

maybe_add_repo_venv intublade "$HOME/dev/repos/intublade" .venv 2.12 "IntuBlade SAM3/HIL validation"
maybe_add_repo_venv vigil-spark-bg "$HOME/dev/repos/vigil-spark" .venv 2.11 "VIGIL vLLM background service"
maybe_add_repo_venv vigil-spark-gb10 "$HOME/dev/repos/vigil-spark" .venv-gb10-accel-py313 2.12 "VIGIL GB10 acceleration tooling"

{
  printf '## Policy\n\n```text\n'
  gb10_accel_print_policy
  printf '\n```\n\n'
  printf '## Audit\n\n```json\n'
  python3 - "$json_report" "${entries[@]}" <<'PY'
from __future__ import annotations

import importlib
import importlib.metadata as md
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


PACKAGES = [
    "torch",
    "torchvision",
    "triton",
    "tensorrt-cu13",
    "torch-tensorrt",
    "cuda-python",
    "cuda-toolkit",
    "onnx",
    "onnxscript",
    "flash-attn",
    "flashinfer-cubin",
    "flashinfer-python",
    "vllm",
]


def run_python(python: Path, code: str) -> dict[str, Any]:
    proc = subprocess.run(
        [str(python), "-c", code],
        capture_output=True,
        check=False,
        text=True,
        timeout=30,
    )
    for line in reversed(proc.stdout.splitlines()):
        line = line.strip()
        if line.startswith("{"):
            try:
                result = json.loads(line)
                result["returncode"] = proc.returncode
                return result
            except json.JSONDecodeError:
                continue
    return {
        "returncode": proc.returncode,
        "error": (proc.stderr or proc.stdout).strip(),
    }


def inspect(label: str, venv: str, expected: str, purpose: str) -> dict[str, Any]:
    python = Path(venv) / "bin" / "python"
    row: dict[str, Any] = {
        "label": label,
        "venv": venv,
        "expected_torch": expected,
        "purpose": purpose,
        "exists": python.exists(),
    }
    if not python.exists():
        row["status"] = "missing"
        return row
    code = f"""
import importlib
import importlib.metadata as md
import json
packages = {PACKAGES!r}
versions = {{}}
for package in packages:
    try:
        versions[package] = md.version(package)
    except md.PackageNotFoundError:
        versions[package] = None
torch_info = {{}}
try:
    import torch
    torch_info = {{
        "version": torch.__version__,
        "cuda_version": getattr(torch.version, "cuda", None),
        "cuda_available": bool(torch.cuda.is_available()),
        "compile_available": hasattr(torch, "compile"),
    }}
    if torch.cuda.is_available():
        torch_info["device"] = torch.cuda.get_device_name(0)
        props = torch.cuda.get_device_properties(0)
        torch_info["compute_capability"] = f"{{props.major}}.{{props.minor}}"
except Exception as exc:
    torch_info = {{"error": repr(exc)}}
optional_imports = {{}}
for name in ["tensorrt", "torch_tensorrt", "flash_attn"]:
    try:
        module = importlib.import_module(name)
        optional_imports[name] = {{"available": True, "version": str(getattr(module, "__version__", "unknown"))}}
    except Exception as exc:
        optional_imports[name] = {{"available": False, "error": str(exc)}}
print(json.dumps({{"versions": versions, "torch": torch_info, "optional_imports": optional_imports}}, sort_keys=True))
"""
    row.update(run_python(python, code))
    torch_version = str(row.get("torch", {}).get("version", ""))
    if expected != "any" and torch_version and not torch_version.startswith(expected):
        row["status"] = "drift"
    elif row.get("returncode", 1) == 0:
        row["status"] = "ok"
    else:
        row["status"] = "error"
    return row


rows = []
for spec in sys.argv[2:]:
    label, venv, expected, purpose = spec.split(":", 3)
    rows.append(inspect(label, venv, expected, purpose))
result = {"ok": not any(row["status"] in {"drift", "error"} for row in rows), "environments": rows}
text = json.dumps(result, indent=2, sort_keys=True)
Path(sys.argv[1]).write_text(text + "\n", encoding="utf-8")
print(text)
PY
  printf '\n```\n'
} >> "$report" 2>&1

log "Torch environment audit report: $report"
log "Torch environment audit JSON: $json_report"
