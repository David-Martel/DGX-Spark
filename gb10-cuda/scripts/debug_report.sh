#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_dirs
report="$GB10_REPORTS/debug-$(timestamp).md"
append_report_header "$report" "GB10 CUDA Debug Report"

section() {
  printf '\n## %s\n\n```text\n' "$1" >> "$report"
  shift
  "$@" >> "$report" 2>&1 || true
  printf '\n```\n' >> "$report"
}

section "State Markers" find "$GB10_STATE" -maxdepth 1 -type f -printf '%f\n'
section "Install Tree" find "$GB10_INSTALL" -maxdepth 3 -type f -o -type l
section "Latest Logs" bash -lc "ls -lt '$GB10_LOGS' | head -80"
section "Recent Reports" bash -lc "ls -lt '$GB10_REPORTS' | head -80"
section "NVIDIA" nvidia-smi
section "CUDA Libraries" bash -lc 'ldconfig -p | egrep "cuda|npp|nvjpeg|cudnn|nvinfer|nvcuvid|nvidia-encode" || true'
section "FFmpeg Optimized" bash -lc "'$GB10_INSTALL/ffmpeg/bin/ffmpeg' -hide_banner -version 2>/dev/null || true; '$GB10_INSTALL/ffmpeg/bin/ffmpeg' -hide_banner -hwaccels 2>/dev/null || true"
section "OpenCV Optimized" bash -lc "LD_LIBRARY_PATH='$GB10_INSTALL/opencv/lib:$GB10_INSTALL/ffmpeg/lib:$CUDA_HOME/lib64' PYTHONPATH='$GB10_INSTALL/opencv/lib/python3.12/site-packages' python3 - <<'PY'
try:
 import cv2
 print(cv2.__version__, cv2.__file__)
 print('cuda devices', cv2.cuda.getCudaEnabledDeviceCount())
except Exception as exc:
 print(repr(exc))
PY"

log "debug report: $report"
