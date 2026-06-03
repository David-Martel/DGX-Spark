#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_dirs
require_cmd uv

image="${TRITON_SERVER_IMAGE:-nvcr.io/nvidia/tritonserver:25.12-py3}"
report="$GB10_REPORTS/install-triton-stack-$(timestamp).md"
append_report_header "$report" "GB10 Triton Stack Install"

{
  printf '## Python Packages\n\n```text\n'
  uv pip install --python "$GB10_VENVS/media/bin/python" torch triton
  uv pip install --python "$GB10_VENVS/media-cpython-3.13.13/bin/python" triton
  printf '\n```\n\n## Triton Server Image\n\n```text\n'
  if sudo docker image inspect "$image" >/dev/null 2>&1; then
    printf 'image already present: %s\n' "$image"
  else
    sudo docker pull "$image"
  fi
  sudo docker image inspect "$image" --format 'id={{.Id}} repoDigests={{json .RepoDigests}} size={{.Size}}'
  printf '\n```\n'
} >> "$report" 2>&1

mkdir -p "$GB10_ROOT/triton/model_repository"
mark_done triton-stack
log "Triton install report: $report"
