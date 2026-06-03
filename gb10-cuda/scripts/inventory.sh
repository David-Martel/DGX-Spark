#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_dirs
report="$GB10_REPORTS/inventory-$(timestamp).md"
append_report_header "$report" "GB10 CUDA Inventory"

section() {
  printf '\n## %s\n\n```text\n' "$1" >> "$report"
  shift
  "$@" >> "$report" 2>&1 || true
  printf '\n```\n' >> "$report"
}

section "OS" bash -lc 'uname -a; lsb_release -a 2>/dev/null || cat /etc/os-release'
section "CPU and Memory" bash -lc 'lscpu; free -h; cat /proc/meminfo | egrep "MemTotal|MemAvailable|SwapTotal|SwapFree|Huge"'
section "Disk" df -h / /home /tmp
section "Toolchain" bash -lc 'for c in gcc g++ cmake ninja make git pkg-config python3 pip3 nvcc nvidia-smi ffmpeg ffprobe gst-inspect-1.0 just; do printf "%-18s" "$c"; command -v "$c" || true; done; gcc --version | head -1; cmake --version | head -1; nvcc --version 2>/dev/null || true'
section "NVIDIA SMI Query" nvidia-smi -q
section "NVIDIA Topology" nvidia-smi topo -m
section "CUDA Unified Memory Probe" bash -lc 'cat <<'"'"'CPP'"'"' | nvcc -x cu -std=c++17 -o /tmp/cuda_um_probe - && /tmp/cuda_um_probe
#include <cuda_runtime.h>
#include <stdio.h>
int main() {
  int n=0;
  cudaGetDeviceCount(&n);
  printf("device_count=%d\n", n);
  for (int d=0; d<n; ++d) {
    cudaDeviceProp p{};
    cudaGetDeviceProperties(&p,d);
    printf("device=%d name=%s cc=%d.%d managedMemory=%d concurrentManagedAccess=%d pageableMemoryAccess=%d pageableUsesHostPT=%d directManagedMemAccessFromHost=%d canMapHostMemory=%d unifiedAddressing=%d asyncEngineCount=%d memoryBusWidth=%d\n", d,p.name,p.major,p.minor,p.managedMemory,p.concurrentManagedAccess,p.pageableMemoryAccess,p.pageableMemoryAccessUsesHostPageTables,p.directManagedMemAccessFromHost,p.canMapHostMemory,p.unifiedAddressing,p.asyncEngineCount,p.memoryBusWidth);
  }
  return 0;
}
CPP'
section "OpenCV Python Build" python3 - <<'PY'
try:
    import cv2
    print("cv2", cv2.__version__, cv2.__file__)
    print(cv2.getBuildInformation())
except Exception as exc:
    print("opencv import failed:", repr(exc))
PY
section "FFmpeg Baseline" bash -lc 'if command -v ffmpeg >/dev/null; then ffmpeg -hide_banner -version; ffmpeg -hide_banner -hwaccels; ffmpeg -hide_banner -encoders | egrep "nvenc|libx264|libx265|av1" || true; else echo "ffmpeg not installed"; fi'
section "GStreamer Baseline" bash -lc 'gst-inspect-1.0 --version 2>/dev/null || true; gst-inspect-1.0 2>/dev/null | egrep -i "nv|cuda|nvidia|v4l2|h264|h265|av1|jpeg|decode|encode" || true'
section "Relevant Packages" bash -lc 'dpkg-query -W | egrep -i "ffmpeg|opencv|cuda|nvidia|tensorrt|nvinfer|vpi|cudnn|nvcodec|gstreamer|nvjpeg|npp|libav|vulkan" || true'

log "inventory report: $report"
