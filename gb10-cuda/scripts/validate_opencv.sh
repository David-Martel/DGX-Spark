#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_dirs
report="$GB10_REPORTS/validate-opencv-$(timestamp).md"
append_report_header "$report" "GB10 OpenCV CUDA Validation"

export LD_LIBRARY_PATH="$GB10_INSTALL/opencv/lib:$GB10_INSTALL/ffmpeg/lib:$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}"
python_exe="${OPENCV_PYTHON:-}"
if [[ -z "$python_exe" ]]; then
  if [[ -x "$GB10_VENVS/media/bin/python" ]]; then
    python_exe="$GB10_VENVS/media/bin/python"
  else
    python_exe="/usr/bin/python3"
  fi
fi
python_site="$("$python_exe" - <<'PY'
import sysconfig
print(sysconfig.get_paths()["platlib"])
PY
)"

{
  printf '## opencv_version\n\n```text\n'
  "$GB10_INSTALL/opencv/bin/opencv_version" --verbose || true
  printf '\n```\n\n## Python CUDA Smoke\n\n```text\n'
  PYTHONPATH="$python_site:${PYTHONPATH:-}" "$python_exe" - <<'PY'
import cv2
import numpy as np
print("cv2", cv2.__version__, cv2.__file__)
print("cuda devices", cv2.cuda.getCudaEnabledDeviceCount())
img = np.zeros((720, 1280, 3), dtype=np.uint8)
img[:, :, 1] = 255
gpu = cv2.cuda_GpuMat()
gpu.upload(img)
resized = cv2.cuda.resize(gpu, (640, 360))
gray = cv2.cuda.cvtColor(resized, cv2.COLOR_BGR2GRAY)
out = gray.download()
print("out", out.shape, out.dtype, int(out.mean()))
info = cv2.getBuildInformation()
for key in ["NVIDIA CUDA", "cuDNN", "cudacodec", "NVIDIA GPU arch"]:
    idx = info.find(key)
    if idx >= 0:
        print(info[idx:idx+300])
PY
  printf '\n```\n'
} >> "$report" 2>&1

PYTHONPATH="$python_site:${PYTHONPATH:-}" "$python_exe" - <<'PY'
import cv2
count = cv2.cuda.getCudaEnabledDeviceCount()
raise SystemExit(0 if count > 0 else 1)
PY

log "OpenCV validation report: $report"
