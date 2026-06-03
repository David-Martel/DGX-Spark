#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_dirs
require_cmd git
require_cmd cmake
require_cmd ninja
require_cmd python3

video_codec_sdk_include="$GB10_INSTALL/video-codec-sdk/include"
if [[ "${REQUIRE_VIDEO_CODEC_SDK:-1}" == "1" ]]; then
  for sdk_header in nvcuvid.h cuviddec.h nvEncodeAPI.h; do
    [[ -f "$video_codec_sdk_include/$sdk_header" ]] || die "missing official Video Codec SDK header: $video_codec_sdk_include/$sdk_header; run just download-gated-sdks with an unlocked Bitwarden session or place the official SDK archive under $GB10_ROOT/sdks"
  done
fi

python_exe="${OPENCV_PYTHON:-}"
if [[ -z "$python_exe" ]]; then
  if [[ -x "$GB10_VENVS/media/bin/python" ]]; then
    python_exe="$GB10_VENVS/media/bin/python"
  else
    python_exe="/usr/bin/python3"
  fi
fi
python_tag="$("$python_exe" - <<'PY'
import sys
print(sys.implementation.cache_tag or f"py{sys.version_info.major}{sys.version_info.minor}")
PY
)"
opencv_build_dir="$GB10_BUILD/opencv-$python_tag"
opencv_marker="build-opencv-$python_tag"
python_include="$("$python_exe" - <<'PY'
import sysconfig
print(sysconfig.get_paths()["include"])
PY
)"
python_packages="$("$python_exe" - <<'PY'
import sysconfig
print(sysconfig.get_paths()["platlib"])
PY
)"
mkdir -p "$python_packages"
if ! "$python_exe" -c 'import numpy' >/dev/null 2>&1; then
  if command -v uv >/dev/null 2>&1; then
    run_logged "opencv-python-numpy-$python_tag" uv pip install --python "$python_exe" numpy
  else
    run_logged "opencv-python-numpy-$python_tag" "$python_exe" -m pip install numpy
  fi
fi
numpy_include="$("$python_exe" - <<'PY'
import numpy
print(numpy.get_include())
PY
)"
python_library="$("$python_exe" - <<'PY'
import os
import sysconfig
libdir = sysconfig.get_config_var("LIBDIR") or ""
ldlibrary = sysconfig.get_config_var("LDLIBRARY") or ""
candidate = os.path.join(libdir, ldlibrary) if libdir and ldlibrary else ""
print(candidate if candidate and os.path.exists(candidate) else "")
PY
)"

if is_done "$opencv_marker" && [[ "${FORCE_RECONFIGURE:-0}" != "1" ]] && [[ -f "$GB10_INSTALL/opencv/lib/pkgconfig/opencv4.pc" ]]; then
  log "OpenCV build already complete for $python_tag; set FORCE_REBUILD=1 to rebuild"
  exit 0
fi

cd "$GB10_SRC"
if [[ ! -d opencv/.git ]]; then
  run_logged clone-opencv git clone --branch 4.x --depth 1 https://github.com/opencv/opencv.git
else
  run_logged update-opencv git -C opencv pull --ff-only
fi
if [[ ! -d opencv_contrib/.git ]]; then
  run_logged clone-opencv-contrib git clone --branch 4.x --depth 1 https://github.com/opencv/opencv_contrib.git
else
  run_logged update-opencv-contrib git -C opencv_contrib pull --ff-only
fi

if [[ "${FORCE_REBUILD:-0}" == "1" ]]; then
  rm -rf "$opencv_build_dir"
fi
mkdir -p "$opencv_build_dir"

cmake_args=(
  -S "$GB10_SRC/opencv"
  -B "$opencv_build_dir"
  -G Ninja
  -D CMAKE_BUILD_TYPE=Release
  -D CMAKE_INSTALL_PREFIX="$GB10_INSTALL/opencv"
  -D OPENCV_EXTRA_MODULES_PATH="$GB10_SRC/opencv_contrib/modules"
  -D OPENCV_GENERATE_PKGCONFIG=ON
  -D BUILD_LIST=core,imgproc,imgcodecs,videoio,highgui,calib3d,features2d,dnn,python3,cudaarithm,cudawarping,cudaimgproc,cudafilters,cudacodec,cudev
  -D WITH_CUDA=ON
  -D CUDA_ARCH_BIN="$CUDA_ARCH_BIN"
  -D CUDA_ARCH_PTX=""
  -D WITH_CUDNN=ON
  -D OPENCV_DNN_CUDA=ON
  -D WITH_CUBLAS=ON
  -D WITH_NPP=ON
  -D WITH_NVCUVID=ON
  -D WITH_NVCUVENC=ON
  -D CUDA_nvcuvid_LIBRARY=/lib/aarch64-linux-gnu/libnvcuvid.so
  -D CUDA_nvidia-encode_LIBRARY=/lib/aarch64-linux-gnu/libnvidia-encode.so
  -D ENABLE_FAST_MATH=ON
  -D CUDA_FAST_MATH=ON
  -D WITH_FFMPEG=ON
  -D WITH_GSTREAMER=ON
  -D WITH_TBB=ON
  -D WITH_OPENCL=ON
  -D BUILD_TESTS=OFF
  -D BUILD_PERF_TESTS=OFF
  -D BUILD_EXAMPLES=OFF
  -D BUILD_opencv_java=OFF
  -D PYTHON3_EXECUTABLE="$python_exe"
  -D PYTHON3_INCLUDE_DIR="$python_include"
  -D PYTHON3_PACKAGES_PATH="$python_packages"
  -D PYTHON3_NUMPY_INCLUDE_DIRS="$numpy_include"
)

if [[ -n "$python_library" ]]; then
  cmake_args+=(-D PYTHON3_LIBRARY="$python_library")
fi

export PATH="$GB10_INSTALL/ffmpeg/bin:$CUDA_HOME/bin:$PATH"
export PKG_CONFIG_PATH="$GB10_INSTALL/ffmpeg/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="$GB10_INSTALL/ffmpeg/lib:$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}"

run_logged "configure-opencv-$python_tag" cmake "${cmake_args[@]}"
run_logged "build-opencv-$python_tag" cmake --build "$opencv_build_dir" --parallel "$MAKE_JOBS"
run_logged "install-opencv-$python_tag" cmake --install "$opencv_build_dir"

mark_done "$opencv_marker"
log "OpenCV installed at $GB10_INSTALL/opencv for $python_tag ($python_exe)"
