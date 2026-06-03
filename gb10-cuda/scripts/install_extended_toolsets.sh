#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_dirs

packages=(
  cuda-ctadvisor-13-0
  cuda-sandbox-dev-13-0
  nvidia-cuda-samples
  libnccl2
  libnccl-dev
  cutensor-cuda-13
  libcutensor2-dev-cuda-13
  cusparselt-cuda-13
  libcusparselt0-dev-cuda-13
  cudss-cuda-13
  libcudss0-dev-cuda-13
  holoscan-cuda-13
  vulkan-tools
  vulkan-validationlayers
  libvulkan-memory-allocator-dev
  libtaskflow-cpp-dev
  libtcmalloc-minimal4t64
  google-perftools
  libsecret-tools
  linux-tools-common
  "linux-tools-$(uname -r)"
  nvhpc-26-3
)

log "dry-running extended toolset install"
dry_log="$GB10_LOGS/extended-toolsets-dry-run-$(timestamp).log"
if ! sudo apt-get install -s "${packages[@]}" 2>&1 | tee "$dry_log"; then
  die "extended toolset dry-run failed; see $dry_log"
fi

if grep -Eq 'Remv|REMOVE|nvidia-driver|linux-image|cuda-toolkit-13-0' "$dry_log"; then
  die "extended toolset dry-run proposes removing/replacing baseline packages; see $dry_log"
fi

log "installing extended NVIDIA/ARM toolsets"
run_logged extended-toolsets-install sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
mark_done extended-toolsets
log "extended toolset install complete"
