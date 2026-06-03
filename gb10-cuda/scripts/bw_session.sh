#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

SERVICE_NAME="gb10-cuda"
ACCOUNT_NAME="bw-session"
DEFAULT_SESSION_FILE="${XDG_RUNTIME_DIR:-$HOME/.cache}/gb10-cuda/bw-session"
SESSION_FILE="${GB10_BW_SESSION_FILE:-$DEFAULT_SESSION_FILE}"

usage() {
  cat <<'EOF'
Usage:
  bw_session.sh status
  bw_session.sh print-session
  bw_session.sh store-session
  bw_session.sh store-env
  bw_session.sh unlock-from-password-file
  bw_session.sh clear

Security model:
  - Prefer BW_SESSION from the current shell or a Secret Service keyring.
  - Fallback session files must be owner-readable only (0600).
  - Master-password files are not created by this script; if explicitly used,
    GB10_BW_MASTER_PASS_FILE must point to a 0600 file.
  - Session values are never written to reports.
EOF
}

have_secret_tool() {
  command -v secret-tool >/dev/null 2>&1
}

is_valid_session() {
  local session="$1"
  [[ -n "$session" ]] || return 1
  BW_SESSION="$session" bw status 2>/dev/null | jq -e '.status == "unlocked"' >/dev/null 2>&1
}

check_private_file() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  local mode owner
  mode="$(stat -c '%a' "$file")"
  owner="$(stat -c '%U' "$file")"
  [[ "$owner" == "$USER" ]] || die "$file is owned by $owner, expected $USER"
  case "$mode" in
    400|600) ;;
    *) die "$file must be chmod 0600 or 0400, found $mode" ;;
  esac
}

read_from_file() {
  local file="$1"
  check_private_file "$file"
  IFS= read -r session < "$file"
  printf '%s' "$session"
}

store_file() {
  local session="$1"
  install -d -m 0700 "$(dirname "$SESSION_FILE")"
  umask 077
  printf '%s\n' "$session" > "$SESSION_FILE"
  chmod 0600 "$SESSION_FILE"
}

store_keyring() {
  local session="$1"
  have_secret_tool || return 1
  printf '%s' "$session" | secret-tool store --label="GB10 Bitwarden Session" service "$SERVICE_NAME" account "$ACCOUNT_NAME"
}

lookup_keyring() {
  have_secret_tool || return 1
  secret-tool lookup service "$SERVICE_NAME" account "$ACCOUNT_NAME" 2>/dev/null || true
}

resolve_session() {
  local session="${BW_SESSION:-}"
  if is_valid_session "$session"; then
    printf '%s' "$session"
    return 0
  fi

  session="$(lookup_keyring)"
  if is_valid_session "$session"; then
    printf '%s' "$session"
    return 0
  fi

  if [[ -f "$SESSION_FILE" ]]; then
    session="$(read_from_file "$SESSION_FILE")"
    if is_valid_session "$session"; then
      printf '%s' "$session"
      return 0
    fi
  fi

  if [[ -n "${GB10_BW_MASTER_PASS_FILE:-}" ]]; then
    check_private_file "$GB10_BW_MASTER_PASS_FILE"
    session="$(bw unlock --raw --passwordfile "$GB10_BW_MASTER_PASS_FILE" 2>/dev/null || true)"
    if is_valid_session "$session"; then
      if have_secret_tool; then
        store_keyring "$session" || store_file "$session"
      else
        store_file "$session"
      fi
      printf '%s' "$session"
      return 0
    fi
  fi

  return 1
}

cmd="${1:-}"
case "$cmd" in
  status)
    if resolve_session >/dev/null; then
      printf 'Bitwarden session available and unlocked\n'
    else
      printf 'Bitwarden session unavailable or locked\n'
      exit 1
    fi
    ;;
  print-session)
    resolve_session
    ;;
  store-session)
    IFS= read -r session
    is_valid_session "$session" || die "provided Bitwarden session is not valid/unlocked"
    if have_secret_tool; then
      store_keyring "$session" || store_file "$session"
    else
      store_file "$session"
    fi
    printf 'Stored Bitwarden session without printing it\n'
    ;;
  store-env)
    [[ -n "${BW_SESSION:-}" ]] || die "BW_SESSION is not set"
    is_valid_session "$BW_SESSION" || die "BW_SESSION is not valid/unlocked"
    if have_secret_tool; then
      store_keyring "$BW_SESSION" || store_file "$BW_SESSION"
    else
      store_file "$BW_SESSION"
    fi
    printf 'Stored BW_SESSION without printing it\n'
    ;;
  unlock-from-password-file)
    [[ -n "${GB10_BW_MASTER_PASS_FILE:-}" ]] || die "set GB10_BW_MASTER_PASS_FILE to a chmod 0600 password file"
    resolve_session >/dev/null
    printf 'Unlocked Bitwarden and stored the session without printing it\n'
    ;;
  clear)
    rm -f "$SESSION_FILE"
    if have_secret_tool; then
      secret-tool clear service "$SERVICE_NAME" account "$ACCOUNT_NAME" >/dev/null 2>&1 || true
    fi
    printf 'Cleared GB10 Bitwarden session stores\n'
    ;;
  -h|--help|help|'')
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
