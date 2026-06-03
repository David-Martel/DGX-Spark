#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_dirs
report="$GB10_REPORTS/benchmark-$(timestamp).md"
csv="$GB10_REPORTS/benchmark-$(timestamp).csv"
dmon="$GB10_REPORTS/benchmark-dmon-$(timestamp).log"
append_report_header "$report" "GB10 CUDA Benchmark"
printf 'name,seconds,command\n' > "$csv"

dmon_pid=""
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi dmon -s pucvmet -d 1 -c 30 > "$dmon" 2>&1 &
  dmon_pid="$!"
  trap 'if [[ -n "${dmon_pid:-}" ]] && kill -0 "$dmon_pid" 2>/dev/null; then kill "$dmon_pid" 2>/dev/null || true; wait "$dmon_pid" 2>/dev/null || true; fi' EXIT
fi

bench() {
  local name="$1"
  shift
  local start end elapsed
  start="$(date +%s.%N)"
  "$@" >> "$report" 2>&1
  end="$(date +%s.%N)"
  elapsed="$(awk "BEGIN {print $end - $start}")"
  printf '%s,%s,"%s"\n' "$name" "$elapsed" "$*" >> "$csv"
  log "$name: ${elapsed}s"
}

sys_ffmpeg="$(command -v ffmpeg || true)"
opt_ffmpeg="$GB10_INSTALL/ffmpeg/bin/ffmpeg"
export LD_LIBRARY_PATH="$GB10_INSTALL/ffmpeg/lib:$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}"
sample="$GB10_BUILD/bench-input-1080p.mp4"
mkdir -p "$GB10_BUILD"

if [[ -x "$opt_ffmpeg" ]]; then
  "$opt_ffmpeg" -hide_banner -y -f lavfi -i testsrc2=size=1920x1080:rate=60 -t 10 -c:v libx264 -preset veryfast "$sample" >> "$report" 2>&1
elif [[ -n "$sys_ffmpeg" ]]; then
  "$sys_ffmpeg" -hide_banner -y -f lavfi -i testsrc2=size=1920x1080:rate=60 -t 10 -c:v libx264 -preset veryfast "$sample" >> "$report" 2>&1
else
  die "no ffmpeg available to generate sample"
fi

if [[ -n "$sys_ffmpeg" ]]; then
  bench "system_ffmpeg_sw_scale" "$sys_ffmpeg" -hide_banner -y -i "$sample" -vf scale=1280:720 -f null -
fi
if [[ -x "$opt_ffmpeg" ]]; then
  bench "opt_ffmpeg_cuda_scale_nvenc" "$opt_ffmpeg" -hide_banner -y -hwaccel cuda -hwaccel_output_format cuda -i "$sample" -vf scale_cuda=1280:720 -c:v h264_nvenc -preset p4 -f null -
fi

{
  printf '\n## OpenCV CPU/CUDA Microbenchmark\n\n```text\n'
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
  PYTHONPATH="$python_site:${PYTHONPATH:-}" \
  LD_LIBRARY_PATH="$GB10_INSTALL/opencv/lib:$GB10_INSTALL/ffmpeg/lib:$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}" \
  "$python_exe" - <<'PY'
import time
import cv2
import numpy as np
img = np.random.randint(0, 255, (2160, 3840, 3), dtype=np.uint8)
iters = 100
t0 = time.perf_counter()
for _ in range(iters):
    out = cv2.resize(img, (1920, 1080))
    gray = cv2.cvtColor(out, cv2.COLOR_BGR2GRAY)
t1 = time.perf_counter()
print("opencv_cpu_resize_cvtColor_seconds", t1 - t0)
if hasattr(cv2, "cuda") and cv2.cuda.getCudaEnabledDeviceCount() > 0:
    gpu = cv2.cuda_GpuMat()
    gpu.upload(img)
    t0 = time.perf_counter()
    for _ in range(iters):
        out = cv2.cuda.resize(gpu, (1920, 1080))
        gray = cv2.cuda.cvtColor(out, cv2.COLOR_BGR2GRAY)
    cv2.cuda_Stream.Null().waitForCompletion()
    t1 = time.perf_counter()
    print("opencv_cuda_resize_cvtColor_seconds", t1 - t0)
else:
    print("opencv_cuda_unavailable")
PY
  printf '\n```\n'
} >> "$report" 2>&1 || true

log "benchmark report: $report"
log "benchmark csv: $csv"
if [[ -f "$dmon" ]]; then
  {
    printf '\n## nvidia-smi dmon\n\n'
    printf -- '- Log: `%s`\n\n```text\n' "$dmon"
    sed -n '1,80p' "$dmon"
    printf '\n```\n'
  } >> "$report"
  log "benchmark dmon: $dmon"
fi
