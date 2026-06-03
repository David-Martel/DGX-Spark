#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_dirs
report="$GB10_REPORTS/cleanup-video-codec-headers-$(timestamp).md"
append_report_header "$report" "GB10 Video Codec Header Cleanup"

cuda_include="$CUDA_HOME/targets/sbsa-linux/include"
{
  printf '## Before\n\n```text\n'
  for h in nvcuvid.h cuviddec.h nvEncodeAPI.h dynlink_nvcuvid.h dynlink_cuviddec.h dynlink_cuda.h dynlink_loader.h; do
    if [[ -f "$cuda_include/$h" ]]; then
      printf 'FOUND %s/%s\n' "$cuda_include" "$h"
    fi
  done
  printf '```\n'
} >> "$report"

if [[ -f "$cuda_include/nvcuvid.h" ]] && grep -q 'dynlink_cuviddec.h' "$cuda_include/nvcuvid.h"; then
  sudo rm -f \
    "$cuda_include/nvcuvid.h" \
    "$cuda_include/cuviddec.h" \
    "$cuda_include/dynlink_nvcuvid.h" \
    "$cuda_include/dynlink_cuviddec.h" \
    "$cuda_include/dynlink_cuda.h" \
    "$cuda_include/dynlink_loader.h" \
    "$cuda_include/nvEncodeAPI.h"
  printf '\n## Action\n\nRemoved non-official `nv-codec-headers` dynamic-loader copies from `%s`.\n' "$cuda_include" >> "$report"
else
  printf '\n## Action\n\nNo dynamic-loader `nv-codec-headers` copy detected in `%s`.\n' "$cuda_include" >> "$report"
fi

{
  printf '\n## After\n\n```text\n'
  for h in nvcuvid.h cuviddec.h nvEncodeAPI.h dynlink_nvcuvid.h dynlink_cuviddec.h dynlink_cuda.h dynlink_loader.h; do
    if [[ -f "$cuda_include/$h" ]]; then
      printf 'FOUND %s/%s\n' "$cuda_include" "$h"
    fi
  done
  printf '```\n'
} >> "$report"

log "cleanup report: $report"
