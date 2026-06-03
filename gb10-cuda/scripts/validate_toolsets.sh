#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_dirs
report="$GB10_REPORTS/validate-toolsets-$(timestamp).md"
append_report_header "$report" "GB10 Extended Toolset Validation"

section() {
  printf '\n## %s\n\n```text\n' "$1" >> "$report"
  shift
  "$@" >> "$report" 2>&1 || true
  printf '\n```\n' >> "$report"
}

section "Commands" bash -lc 'for c in nvcc nsys ncu cuobjdump cuda-gdb compute-sanitizer cu++filt ctadvisor nvc nvc++ nvfortran trtexec vulkaninfo; do printf "%-22s" "$c"; command -v "$c" || true; done'
section "NVIDIA Libraries" bash -lc 'ldconfig -p | egrep "nvinfer|cudnn|nccl|cutensor|cusparselt|cudss|nvcuvid|nvidia-encode|nvidia-opticalflow|holoscan|cuda" | sort || true'
section "Headers" bash -lc 'for h in /opt/gb10-cuda/install/video-codec-sdk/include/nvcuvid.h /opt/gb10-cuda/install/video-codec-sdk/include/cuviddec.h /opt/gb10-cuda/install/video-codec-sdk/include/nvEncodeAPI.h /usr/local/cuda/targets/sbsa-linux/include/nvcuvid.h /usr/local/cuda/targets/sbsa-linux/include/nvEncodeAPI.h /usr/include/aarch64-linux-gnu/cudnn.h /usr/include/aarch64-linux-gnu/NvInfer.h /usr/include/cutensor.h /usr/include/cusparseLt.h /usr/include/cudss.h /opt/nvidia/holoscan/include/holoscan/holoscan.hpp; do test -e "$h" && echo "FOUND $h" || echo "MISSING $h"; done'
section "TensorRT" bash -lc 'trtexec --version 2>/dev/null || trtexec --help 2>/dev/null | head -40 || true'
section "CUDA Samples" bash -lc 'dpkg -L nvidia-cuda-samples 2>/dev/null | head -80 || true'
section "HPC SDK" bash -lc 'find /opt/nvidia/hpc_sdk -maxdepth 4 -type f \( -name nvc -o -name nvc++ -o -name nvfortran \) -print 2>/dev/null | sort | head -40; /opt/nvidia/hpc_sdk/Linux_aarch64/26.3/compilers/bin/nvc++ --version 2>/dev/null || true'
section "Holoscan" bash -lc 'dpkg-query -W | egrep "holoscan" || true; find /opt /usr -maxdepth 4 -type f -name "*holoscan*" 2>/dev/null | head -80'
section "Vulkan" bash -lc 'vulkaninfo --summary 2>/dev/null || true'

log "toolset validation report: $report"
