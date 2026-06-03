#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_dirs
rm -rf "$GB10_BUILD/ffmpeg" "$GB10_BUILD/opencv"
rm -f "$GB10_STATE/build-ffmpeg.done" "$GB10_STATE/build-opencv.done"
log "removed FFmpeg/OpenCV build trees and build state markers"
