#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_dirs
ffmpeg_bin="$GB10_INSTALL/ffmpeg/bin/ffmpeg"
[[ -x "$ffmpeg_bin" ]] || die "optimized ffmpeg not found at $ffmpeg_bin"
export LD_LIBRARY_PATH="$GB10_INSTALL/ffmpeg/lib:$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}"

report="$GB10_REPORTS/validate-ffmpeg-$(timestamp).md"
append_report_header "$report" "GB10 FFmpeg Validation"

{
  printf '## Version\n\n```text\n'
  "$ffmpeg_bin" -hide_banner -version
  printf '\n```\n\n## Hardware Accels\n\n```text\n'
  "$ffmpeg_bin" -hide_banner -hwaccels
  printf '\n```\n\n## NVIDIA Encoders\n\n```text\n'
  "$ffmpeg_bin" -hide_banner -encoders | grep -Ei 'nvenc|av1|h264|hevc' || true
  printf '\n```\n\n## CUDA Filters\n\n```text\n'
  "$ffmpeg_bin" -hide_banner -filters | grep -Ei 'cuda|npp|scale' || true
  printf '\n```\n'
} >> "$report" 2>&1

hwaccels="$("$ffmpeg_bin" -hide_banner -hwaccels)"
encoders="$("$ffmpeg_bin" -hide_banner -encoders)"
grep -q cuda <<<"$hwaccels" || die "CUDA hwaccel missing"
grep -q h264_nvenc <<<"$encoders" || die "h264_nvenc missing"

sample="$GB10_BUILD/ffmpeg-smoke-input.mp4"
out="$GB10_BUILD/ffmpeg-smoke-output.mp4"
"$ffmpeg_bin" -hide_banner -y -f lavfi -i testsrc2=size=1280x720:rate=30 -t 3 -c:v libx264 "$sample" >> "$report" 2>&1
"$ffmpeg_bin" -hide_banner -y -hwaccel cuda -hwaccel_output_format cuda -i "$sample" -vf scale_cuda=640:360 -c:v h264_nvenc -preset p4 "$out" >> "$report" 2>&1
"$ffmpeg_bin" -hide_banner -v error -i "$out" -f null - >> "$report" 2>&1

log "FFmpeg validation report: $report"
