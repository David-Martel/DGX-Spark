#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_dirs
sdk_dir="$GB10_ROOT/sdks"
mkdir -p "$sdk_dir" "$GB10_INSTALL/video-codec-compat/include"

report="$GB10_REPORTS/sdk-downloads-$(timestamp).md"
append_report_header "$report" "GB10 NVIDIA SDK Download Probe"

download_probe() {
  local name="$1"
  local url="$2"
  local out="$sdk_dir/$3"
  printf '\n## %s\n\n- URL: `%s`\n- Output: `%s`\n\n```text\n' "$name" "$url" "$out" >> "$report"
  if curl -L --fail --connect-timeout 20 --max-time 180 -o "$out" "$url" >> "$report" 2>&1; then
    file "$out" >> "$report" 2>&1 || true
    unzip -t "$out" >> "$report" 2>&1 || true
  else
    printf 'download failed or gated\n' >> "$report"
  fi
  printf '\n```\n' >> "$report"
}

download_probe \
  "Video Codec SDK Interface 13.0.37" \
  "https://developer.nvidia.com/downloads/video-codec-sdk/13.0.37/video_codec_interface_13.0.37.zip" \
  "video_codec_interface_13.0.37.zip"

download_probe \
  "Video Codec SDK 13.0.37 Full" \
  "https://developer.nvidia.com/downloads/video-codec-sdk/13.0.37/video_codec_sdk_13.0.37.zip" \
  "video_codec_sdk_13.0.37.zip"

download_probe \
  "Optical Flow SDK" \
  "https://developer.nvidia.com/downloads/optical-flow-sdk/optical_flow_sdk.zip" \
  "optical_flow_sdk.zip"

compat="$GB10_INSTALL/video-codec-compat/include"
cp -f "$GB10_INSTALL/ffmpeg/include/ffnvcodec/nvEncodeAPI.h" "$compat/nvEncodeAPI.h"
cp -f "$GB10_INSTALL/ffmpeg/include/ffnvcodec/dynlink_nvcuvid.h" "$compat/dynlink_nvcuvid.h"
cp -f "$GB10_INSTALL/ffmpeg/include/ffnvcodec/dynlink_nvcuvid.h" "$compat/nvcuvid.h"
cp -f "$GB10_INSTALL/ffmpeg/include/ffnvcodec/dynlink_cuviddec.h" "$compat/dynlink_cuviddec.h"
cp -f "$GB10_INSTALL/ffmpeg/include/ffnvcodec/dynlink_cuviddec.h" "$compat/cuviddec.h"
cp -f "$GB10_INSTALL/ffmpeg/include/ffnvcodec/dynlink_cuda.h" "$compat/dynlink_cuda.h"
cp -f "$GB10_INSTALL/ffmpeg/include/ffnvcodec/dynlink_loader.h" "$compat/dynlink_loader.h"

{
  printf '\n## Local Video Codec Compatibility Headers\n\n```text\n'
  find "$compat" -maxdepth 1 -type f -printf '%f\n' | sort
  printf '\n```\n'
} >> "$report"

mark_done sdk-downloads
log "SDK download/probe report: $report"
