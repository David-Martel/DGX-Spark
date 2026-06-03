#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_dirs
require_cmd bw
require_cmd jq
require_cmd curl
require_cmd unzip

sdk_dir="$GB10_ROOT/sdks"
mkdir -p "$sdk_dir"
report="$GB10_REPORTS/nvidia-gated-sdk-downloads-$(timestamp).md"
append_report_header "$report" "GB10 NVIDIA Gated SDK Download Probe"

remove_unofficial_cuda_codec_headers() {
  local cuda_include="$CUDA_HOME/targets/sbsa-linux/include"
  [[ -d "$cuda_include" ]] || return 0
  if [[ -f "$cuda_include/nvcuvid.h" ]] && grep -q 'dynlink_cuviddec.h' "$cuda_include/nvcuvid.h"; then
    sudo rm -f \
      "$cuda_include/nvcuvid.h" \
      "$cuda_include/cuviddec.h" \
      "$cuda_include/dynlink_nvcuvid.h" \
      "$cuda_include/dynlink_cuviddec.h" \
      "$cuda_include/dynlink_cuda.h" \
      "$cuda_include/dynlink_loader.h" \
      "$cuda_include/nvEncodeAPI.h"
    printf '\n## CUDA Header Cleanup\n\nRemoved prior `nv-codec-headers` dynamic-loader copies from `%s`.\n' "$cuda_include" >> "$report"
  fi
}

zip_entry() {
  local zip="$1"
  local header="$2"
  unzip -Z1 "$zip" | awk -v header="$header" -F/ '$NF == header { print; exit }'
}

install_video_codec_headers_from_zip() {
  local zip="$1"
  [[ -f "$zip" ]] || return 1
  if ! unzip -t "$zip" >/dev/null 2>&1; then
    return 1
  fi

  local nvcuvid cuviddec nvencode
  nvcuvid="$(zip_entry "$zip" nvcuvid.h)"
  cuviddec="$(zip_entry "$zip" cuviddec.h)"
  nvencode="$(zip_entry "$zip" nvEncodeAPI.h)"
  [[ -n "$nvcuvid" && -n "$cuviddec" && -n "$nvencode" ]] || return 1

  local include="$GB10_INSTALL/video-codec-sdk/include"
  mkdir -p "$include"
  unzip -p "$zip" "$nvcuvid" > "$include/nvcuvid.h"
  unzip -p "$zip" "$cuviddec" > "$include/cuviddec.h"
  unzip -p "$zip" "$nvencode" > "$include/nvEncodeAPI.h"

  if grep -q 'dynlink_cuviddec.h' "$include/nvcuvid.h"; then
    rm -f "$include/nvcuvid.h" "$include/cuviddec.h" "$include/nvEncodeAPI.h"
    return 1
  fi
  if ! grep -q 'cuvidDecodePicture' "$include/cuviddec.h"; then
    rm -f "$include/nvcuvid.h" "$include/cuviddec.h" "$include/nvEncodeAPI.h"
    return 1
  fi

  remove_unofficial_cuda_codec_headers
  sudo install -m 0644 "$include/nvcuvid.h" "$CUDA_HOME/targets/sbsa-linux/include/nvcuvid.h"
  sudo install -m 0644 "$include/cuviddec.h" "$CUDA_HOME/targets/sbsa-linux/include/cuviddec.h"
  sudo install -m 0644 "$include/nvEncodeAPI.h" "$CUDA_HOME/targets/sbsa-linux/include/nvEncodeAPI.h"
  {
    printf '\n## Official Video Codec SDK Headers\n\n'
    printf -- '- Source archive: `%s`\n' "$zip"
    printf -- '- Installed include: `%s`\n' "$include"
    printf -- '- CUDA include: `%s/targets/sbsa-linux/include`\n' "$CUDA_HOME"
    printf '\n```text\n'
    ls -l "$include"/nvcuvid.h "$include"/cuviddec.h "$include"/nvEncodeAPI.h
    printf '```\n'
  } >> "$report"
  mark_done video-codec-sdk-headers
  return 0
}

install_existing_video_codec_sdk() {
  local zip
  while IFS= read -r zip; do
    install_video_codec_headers_from_zip "$zip" && return 0
  done < <(find "$sdk_dir" "$HOME/Downloads" -maxdepth 1 -type f \( -iname '*video*codec*.zip' -o -iname '*Video_Codec*.zip' -o -iname '*nvcodec*.zip' \) 2>/dev/null | sort)
  return 1
}

record_download() {
  local name="$1"
  local out="$2"
  printf '\n## %s\n\n- Output: `%s`\n\n```text\n' "$name" "$out" >> "$report"
  file "$out" >> "$report" 2>&1 || true
  unzip -t "$out" >> "$report" 2>&1 || true
  printf '\n```\n' >> "$report"
}

if install_existing_video_codec_sdk; then
  log "official Video Codec SDK headers installed from existing archive. Report: $report"
  exit 0
fi

session="$("$SCRIPT_DIR/bw_session.sh" print-session 2>/dev/null || true)"
if [[ -z "$session" ]]; then
  {
    printf '## Bitwarden\n\n'
    printf 'No unlocked Bitwarden session was available. Provide one with:\n\n'
    printf '```bash\n'
    printf 'export BW_SESSION=... && %s/bw_session.sh store-env\n' "$SCRIPT_DIR"
    printf '# or use a chmod 0600 password file explicitly:\n'
    printf 'GB10_BW_MASTER_PASS_FILE=/path/to/file %s/bw_session.sh unlock-from-password-file\n' "$SCRIPT_DIR"
    printf '```\n'
  } >> "$report"
  log "gated SDK download skipped; Bitwarden locked. Report: $report"
  exit 0
fi

tmpdir="$(mktemp -d)"
chmod 0700 "$tmpdir"
trap 'rm -rf "$tmpdir"' EXIT
items_json="$tmpdir/bw-nvidia-items.json"
headers_file="$tmpdir/curl-headers.conf"

if ! BW_SESSION="$session" bw list items --search nvidia > "$items_json"; then
  printf '## Bitwarden\n\nFailed to list NVIDIA items from Bitwarden.\n' >> "$report"
  log "Bitwarden item lookup failed. Report: $report"
  exit 0
fi
chmod 0600 "$items_json"

{
  printf '## Bitwarden NVIDIA Items\n\n'
  printf 'Only non-secret item names and IDs are recorded.\n\n'
  printf '```text\n'
  jq -r '.[] | [.name, .id] | @tsv' "$items_json" | sed 's/\t/  /g'
  printf '```\n'
} >> "$report"

{
  printf '\n## Bitwarden NVIDIA Attachments\n\n'
  printf 'Only non-secret attachment names and parent item IDs are recorded.\n\n'
  printf '```text\n'
  jq -r '.[] | . as $item | (.attachments // [])[]? | [$item.id, .id, .fileName] | @tsv' "$items_json" | sed 's/\t/  /g'
  printf '```\n'
} >> "$report"

while IFS=$'\t' read -r item_id attachment_id file_name; do
  [[ -n "$item_id" && -n "$attachment_id" && -n "$file_name" ]] || continue
  case "$file_name" in
    *ideo*[Cc]odec*.zip|*IDEO*[Cc]ODEC*.zip|*nvcodec*.zip|*NVCODEC*.zip|*Optical*[Ff]low*.zip|*optical*flow*.zip)
      out="$sdk_dir/$file_name"
      if BW_SESSION="$session" bw get attachment "$attachment_id" --itemid "$item_id" --output "$out" >/dev/null; then
        chmod 0600 "$out"
        record_download "Bitwarden Attachment: $file_name" "$out"
        install_video_codec_headers_from_zip "$out" || true
      fi
      ;;
  esac
done < <(jq -r '.[] | . as $item | (.attachments // [])[]? | [$item.id, .id, .fileName] | @tsv' "$items_json")

cookie="$(jq -r '
  [.[]
   | (.fields // [])
   | .[]
   | select((.name | ascii_upcase) as $n
            | $n == "NVIDIA_DEVELOPER_COOKIE"
              or $n == "NVIDIA_DEV_COOKIE"
              or $n == "DEVELOPER_NVIDIA_COOKIE")
   | .value][0] // ""
' "$items_json")"

ngc_key_present="$(jq -r '
  [.[]
   | (.fields // [])
   | .[]
   | select((.name | ascii_upcase) == "NGC_API_KEY")
   | .value][0] // ""
' "$items_json" | awk 'length($0)>0 {print "yes"; found=1} END {if (!found) print "no"}')"

{
  printf '\n## Usable Credential Fields\n\n'
  printf -- '- NVIDIA developer cookie field present: `%s`\n' "$([[ -n "$cookie" ]] && printf yes || printf no)"
  printf -- '- NGC API key field present: `%s`\n' "$ngc_key_present"
  printf '\n'
} >> "$report"

if [[ -z "$cookie" ]]; then
  {
    printf 'No `NVIDIA_DEVELOPER_COOKIE`, `NVIDIA_DEV_COOKIE`, or '
    printf '`DEVELOPER_NVIDIA_COOKIE` custom field was found. NVIDIA Developer '
    printf 'downloads use browser-authenticated flows, so login/password fields '
    printf 'alone are not replayed by this script.\n'
  } >> "$report"
  log "no NVIDIA developer cookie field found. Report: $report"
  exit 0
fi

printf 'header = "Cookie: %s"\n' "$cookie" > "$headers_file"
chmod 0600 "$headers_file"

download_with_cookie() {
  local name="$1"
  local url="$2"
  local out="$sdk_dir/$3"
  printf '\n## %s\n\n- URL: `%s`\n- Output: `%s`\n\n```text\n' "$name" "$url" "$out" >> "$report"
  if curl --config "$headers_file" -L --fail --connect-timeout 20 --max-time 300 -o "$out" "$url" >> "$report" 2>&1; then
    file "$out" >> "$report" 2>&1 || true
    unzip -t "$out" >> "$report" 2>&1 || true
    install_video_codec_headers_from_zip "$out" || true
  else
    printf 'download failed or remained gated\n' >> "$report"
  fi
  printf '\n```\n' >> "$report"
}

download_with_cookie \
  "Video Codec SDK Interface 13.0.37" \
  "https://developer.nvidia.com/downloads/video-codec-sdk/13.0.37/video_codec_interface_13.0.37.zip" \
  "video_codec_interface_13.0.37.zip"

download_with_cookie \
  "Video Codec SDK 13.0.37 Full" \
  "https://developer.nvidia.com/downloads/video-codec-sdk/13.0.37/video_codec_sdk_13.0.37.zip" \
  "video_codec_sdk_13.0.37.zip"

download_with_cookie \
  "Optical Flow SDK" \
  "https://developer.nvidia.com/downloads/optical-flow-sdk/optical_flow_sdk.zip" \
  "optical_flow_sdk.zip"

mark_done nvidia-gated-sdk-downloads
log "gated NVIDIA SDK download/probe report: $report"
