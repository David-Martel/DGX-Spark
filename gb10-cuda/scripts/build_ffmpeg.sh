#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_dirs
require_cmd git
require_cmd make
require_cmd gcc

if is_done build-ffmpeg && [[ -x "$GB10_INSTALL/ffmpeg/bin/ffmpeg" ]]; then
  log "FFmpeg build already complete; set FORCE_REBUILD=1 to rebuild"
  exit 0
fi

cd "$GB10_SRC"
if [[ ! -d nv-codec-headers/.git ]]; then
  run_logged clone-nv-codec-headers git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git
else
  run_logged update-nv-codec-headers git -C nv-codec-headers pull --ff-only
fi

run_logged install-nv-codec-headers bash -lc "cd '$GB10_SRC/nv-codec-headers' && make -j'$MAKE_JOBS' && sudo make PREFIX='$GB10_INSTALL/ffmpeg' install"

if [[ ! -d ffmpeg/.git ]]; then
  rm -rf ffmpeg
  run_logged clone-ffmpeg git clone --depth 1 https://github.com/FFmpeg/FFmpeg.git ffmpeg
else
  run_logged update-ffmpeg git -C ffmpeg pull --ff-only || true
fi

if [[ "${FORCE_REBUILD:-0}" == "1" ]]; then
  rm -rf "$GB10_BUILD/ffmpeg"
fi
mkdir -p "$GB10_BUILD/ffmpeg"

cd "$GB10_BUILD/ffmpeg"
export PKG_CONFIG_PATH="$GB10_INSTALL/ffmpeg/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export PATH="$CUDA_HOME/bin:$PATH"

configure_flags=(
  --prefix="$GB10_INSTALL/ffmpeg"
  --pkg-config-flags=--static
  --extra-cflags="-I$CUDA_HOME/include -I$GB10_INSTALL/ffmpeg/include"
  --extra-ldflags="-L$CUDA_HOME/lib64 -L$GB10_INSTALL/ffmpeg/lib"
  --extra-libs="-lpthread -lm"
  --ld=g++
  --enable-gpl
  --enable-nonfree
  --enable-cuda-nvcc
  --enable-cuda-llvm
  --enable-cuvid
  --enable-nvenc
  --enable-ffnvcodec
  --enable-libx264
  --enable-libx265
  --enable-libvpx
  --enable-libopus
  --enable-libass
  --enable-libfreetype
  --enable-libfontconfig
  --enable-libfribidi
  --enable-libharfbuzz
  --enable-libaom
  --enable-libdav1d
  --enable-openssl
  --enable-shared
  --disable-static
)

run_logged configure-ffmpeg "$GB10_SRC/ffmpeg/configure" "${configure_flags[@]}"
run_logged make-ffmpeg make -j"$MAKE_JOBS"
run_logged install-ffmpeg make install

mark_done build-ffmpeg
log "FFmpeg installed at $GB10_INSTALL/ffmpeg"
