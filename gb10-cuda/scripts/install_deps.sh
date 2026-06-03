#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_dirs

apt_install=(
  just
  ffmpeg
  gstreamer1.0-libav
  gstreamer1.0-plugins-bad
  gstreamer1.0-plugins-ugly
  build-essential
  git
  cmake
  ninja-build
  pkg-config
  yasm
  nasm
  autoconf
  automake
  libtool
  curl
  ca-certificates
  python3-dev
  python3-venv
  python3-pip
  python3-numpy
  libnuma-dev
  libssl-dev
  libx264-dev
  libx265-dev
  libvpx-dev
  libfdk-aac-dev
  libopus-dev
  libass-dev
  libfreetype6-dev
  libfontconfig1-dev
  libfribidi-dev
  libharfbuzz-dev
  libvorbis-dev
  libaom-dev
  libdav1d-dev
  libsvtav1-dev
  libdrm-dev
  libva-dev
  libvdpau-dev
  libgtk-3-dev
  libtbb-dev
  libjpeg-dev
  libpng-dev
  libtiff-dev
  libopenblas-dev
  libeigen3-dev
  libprotobuf-dev
  protobuf-compiler
  libgoogle-glog-dev
  libgflags-dev
  libhdf5-dev
  libgstreamer1.0-dev
  libgstreamer-plugins-base1.0-dev
  libavcodec-dev
  libavformat-dev
  libavutil-dev
  libswscale-dev
  libavfilter-dev
  libavdevice-dev
  libpostproc-dev
  libswresample-dev
  libcudnn9-cuda-13
  libcudnn9-dev-cuda-13
  libnvjpeg2k0-dev-cuda-13
)

log "refreshing apt metadata"
run_logged apt-update sudo apt-get update

log "installing baseline/system dependencies"
run_logged apt-install sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${apt_install[@]}"

log "checking TensorRT dry-run before install"
if sudo apt-get install -s tensorrt-dev tensorrt-libs libnvinfer-bin | tee "$GB10_LOGS/tensorrt-dry-run-$(timestamp).log" | grep -Eq 'Remv|REMOVE|nvidia-driver|cuda-toolkit-13-0'; then
  log "TensorRT dry-run indicates driver/CUDA baseline changes; skipping TensorRT install"
  touch "$GB10_STATE/tensorrt-skipped-needs-review.done"
else
  run_logged tensorrt-install sudo DEBIAN_FRONTEND=noninteractive apt-get install -y tensorrt-dev tensorrt-libs libnvinfer-bin
fi

mark_done install-deps
log "dependency install complete"
