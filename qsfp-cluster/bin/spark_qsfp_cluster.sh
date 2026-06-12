#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QSFP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ARTIFACT_ROOT="${SPARK_QSFP_ARTIFACT_ROOT:-$QSFP_ROOT/artifacts}"
RUN_ID="${SPARK_QSFP_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
RUN_DIR="$ARTIFACT_ROOT/$RUN_ID"

NVSYNC="${SPARK_QSFP_NVSYNC:-/opt/NVIDIA Sync/resources/bin/nvsync-arm64}"
ALIASES="${SPARK_QSFP_ALIASES:-nvsync-mgmt-3066 nvsync-mgmt-0060}"
IP_BASE="${SPARK_QSFP_IP_BASE:-10.55}"
TOPOLOGY="${SPARK_QSFP_TOPOLOGY:-direct_2}"
DISCOVERY_TIMEOUT="${SPARK_QSFP_DISCOVERY_TIMEOUT:-12}"
NVSYNC_TIMEOUT="${SPARK_QSFP_NVSYNC_TIMEOUT:-180}"
NVSYNC_DOCTOR_TIMEOUT="${SPARK_QSFP_NVSYNC_DOCTOR_TIMEOUT:-15}"
SSH_TIMEOUT="${SPARK_QSFP_SSH_TIMEOUT:-18}"
APPLY=0
SETUP_CLUSTER_SSH=0
CLEAN_CONFLICTS=0
SKIP_NVSYNC_TEST=0
VERBOSE=0

usage() {
  cat <<'USAGE'
Usage: spark_qsfp_cluster.sh <command> [options]

Commands:
  doctor          Inspect local prerequisites, NVIDIA Sync, CX7 links, and aliases.
  preflight       Run NVIDIA Sync topology-preflight for configured aliases.
  detect          Detect topology and write generated plan artifacts.
  snapshot-live   Snapshot the current Sync-managed CX7 addresses into plan artifacts.
  configure       Detect, backup netplan, optionally clean conflicts, apply Sync netplan, verify.
  verify          Verify runtime IPs and ping targets from the latest detected topology.
  cluster-ssh     Configure node-to-node SSH over the first Sync-managed subnet.
  rdma-test       Run focused ib_write_bw tests for both active RoCE paths.
  cleanup-tests   Kill stale iperf/perftest processes on all configured nodes.
  recover         Re-run cleanup-tests, verify, and print rollback guidance.

Options:
  --aliases "A B"        Management SSH aliases. Default: nvsync-mgmt-3066 nvsync-mgmt-0060.
  --ip-base X.Y          First two octets for NVIDIA Sync IP assignment. Default: 10.55.
  --apply                Required by configure before changing network state.
  --clean-conflicts      Delete active NetworkManager profiles bound to CX7 interfaces before apply.
  --cluster-ssh          Run node-to-node SSH setup after successful configure.
  --skip-nvsync-test     Skip NVIDIA Sync test-network in configure.
  --verbose              Pass --verbose to nvsync.
  -h, --help             Show this help.

Environment:
  SPARK_QSFP_ALIASES       Same as --aliases.
  SPARK_QSFP_NVSYNC        Path to nvsync helper.
  SPARK_QSFP_IP_BASE       Same as --ip-base.
  SPARK_QSFP_RUN_ID        Override artifact run id.
  SPARK_QSFP_ARTIFACT_ROOT Artifact directory root.
  SPARK_QSFP_NVSYNC_TIMEOUT Seconds before a Sync subcommand is failed. Default: 180.
  SPARK_QSFP_SSH_TIMEOUT   Seconds before direct SSH probes are failed. Default: 18.

The script is intentionally conservative. It uses NVIDIA Sync as the primary
configuration engine, snapshots netplan before mutation, and writes JSON/text
artifacts for every run.
USAGE
}

log() {
  printf '[%s] %s\n' "$(date -Is)" "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

read_aliases() {
  # Split the space-separated alias list robustly (avoids SC2206 globbing/
  # word-splitting surprises if an alias ever contains a glob char).
  read -r -a ALIAS_ARRAY <<< "$ALIASES"
  if [[ "${#ALIAS_ARRAY[@]}" -lt 2 || "${#ALIAS_ARRAY[@]}" -gt 4 ]]; then
    die "expected 2-4 aliases, got: $ALIASES"
  fi
}

nvsync_cmd() {
  if [[ "$VERBOSE" -eq 1 ]]; then
    timeout "$NVSYNC_TIMEOUT" "$NVSYNC" "$@" --verbose
  else
    timeout "$NVSYNC_TIMEOUT" "$NVSYNC" "$@"
  fi
}

doctor_nvsync() {
  if [[ "$VERBOSE" -eq 1 ]]; then
    timeout "$NVSYNC_DOCTOR_TIMEOUT" "$NVSYNC" "$@" --verbose
  else
    timeout "$NVSYNC_DOCTOR_TIMEOUT" "$NVSYNC" "$@"
  fi
}

password_stdin() {
  local alias
  for alias in "${ALIAS_ARRAY[@]}"; do
    printf '%s:\n' "$alias"
  done
}

ensure_run_dir() {
  mkdir -p "$RUN_DIR"
}

latest_link() {
  ensure_run_dir
  ln -sfn "$RUN_DIR" "$ARTIFACT_ROOT/latest"
}

resolve_artifact_run_dir() {
  local required_file="$1"
  local found=""
  if [[ -f "$RUN_DIR/$required_file" ]]; then
    return 0
  fi
  if [[ -f "$ARTIFACT_ROOT/latest/$required_file" ]]; then
    RUN_DIR="$(readlink -f "$ARTIFACT_ROOT/latest")"
    return 0
  fi
  found="$(
    find "$ARTIFACT_ROOT" -mindepth 2 -maxdepth 2 -type f -name "$required_file" \
      -printf '%T@ %h\n' 2>/dev/null \
      | sort -nr \
      | awk 'NR == 1 {print $2}'
  )"
  if [[ -n "$found" && -f "$found/$required_file" ]]; then
    RUN_DIR="$found"
    return 0
  fi
  return 1
}

remote() {
  local alias="$1"
  shift
  timeout "$SSH_TIMEOUT" ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=8 \
    -o ConnectionAttempts=1 \
    -o ServerAliveInterval=5 \
    -o ServerAliveCountMax=2 \
    "$alias" "$@"
}

doctor() {
  read_aliases
  ensure_run_dir
  latest_link
  {
    printf 'run_id=%s\n' "$RUN_ID"
    printf 'hostname=%s\n' "$(hostname)"
    printf 'aliases=%s\n' "$ALIASES"
    printf 'nvsync=%s\n' "$NVSYNC"
    printf '\n[nvsync]\n'
    if [[ -x "$NVSYNC" ]]; then "$NVSYNC" version || true; else echo "missing"; fi
    printf '\n[local links]\n'
    if command -v ibdev2netdev >/dev/null; then ibdev2netdev || true; fi
    if command -v rdma >/dev/null; then rdma link || true; fi
    ip -br link || true
    ip -br addr || true
  } | tee "$RUN_DIR/doctor-local.txt"

  local alias
  for alias in "${ALIAS_ARRAY[@]}"; do
    log "checking alias $alias"
    {
      printf '[ssh]\n'
      ssh -G "$alias" 2>/dev/null | awk '/^(host|hostname|user|identityfile|proxycommand|identitiesonly) /'
      printf '\n[remote]\n'
      remote "$alias" 'hostname; whoami; sudo -n true && echo sudo_ok || echo sudo_needs_password' || true
      printf '\n[system]\n'
      doctor_nvsync inspect system "$alias" || true
      printf '\n[sudo]\n'
      doctor_nvsync inspect sudo "$alias" || true
      printf '\n[links]\n'
      remote "$alias" 'ibdev2netdev 2>/dev/null || true; rdma link 2>/dev/null || true; ip -br addr' || true
    } | tee "$RUN_DIR/doctor-$alias.txt"
  done
}

preflight() {
  read_aliases
  ensure_run_dir
  latest_link
  password_stdin | nvsync_cmd integration spark topology-preflight "${ALIAS_ARRAY[@]}" --password-stdin \
    | tee "$RUN_DIR/topology-preflight.jsonl"
}

detect() {
  read_aliases
  ensure_run_dir
  latest_link
  password_stdin | nvsync_cmd integration spark detect-topology "${ALIAS_ARRAY[@]}" \
    --password-stdin --ip-base "$IP_BASE" --discovery-timeout "$DISCOVERY_TIMEOUT" \
    | tee "$RUN_DIR/detect-topology.jsonl"
  python3 "$QSFP_ROOT/lib/extract_nvsync_plan.py" "$RUN_DIR/detect-topology.jsonl" "$RUN_DIR"
}

snapshot_live() {
  read_aliases
  ensure_run_dir
  latest_link
  local alias
  for alias in "${ALIAS_ARRAY[@]}"; do
    log "capturing live CX7 state from $alias"
    remote "$alias" "ip -j addr" > "$RUN_DIR/live-ip-$alias.json"
    remote "$alias" "ibdev2netdev 2>/dev/null || true" > "$RUN_DIR/live-ibdev2netdev-$alias.txt"
    remote "$alias" "show_gids 2>/dev/null || true" > "$RUN_DIR/live-show-gids-$alias.txt"
  done
  python3 "$QSFP_ROOT/lib/build_live_plan.py" "$RUN_DIR" --ip-base "$IP_BASE" "${ALIAS_ARRAY[@]}"
}

backup_netplan() {
  local alias stamp
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  for alias in "${ALIAS_ARRAY[@]}"; do
    log "backing up /etc/netplan on $alias"
    remote "$alias" "sudo -n cp -a /etc/netplan /etc/netplan.backup.nvsync-$stamp && echo /etc/netplan.backup.nvsync-$stamp" \
      | tee -a "$RUN_DIR/netplan-backups.txt"
  done
}

clean_conflicts() {
  local alias interfaces_csv
  interfaces_csv="$(python3 "$QSFP_ROOT/lib/extract_nvsync_plan.py" "$RUN_DIR/detect-topology.jsonl" "$RUN_DIR" --print-interfaces)"
  for alias in "${ALIAS_ARRAY[@]}"; do
    local ifaces
    ifaces="$(awk -F= -v a="$alias" '$1 == a {print $2}' <<<"$interfaces_csv")"
    [[ -n "$ifaces" ]] || continue
    log "cleaning active NetworkManager profiles on $alias for CX7 interfaces: $ifaces"
    remote "$alias" "python3 - '$ifaces' <<'PY'
import subprocess
import sys

targets = set(sys.argv[1].split(','))
rows = subprocess.run(
    ['nmcli', '-t', '-f', 'NAME,DEVICE', 'con', 'show', '--active'],
    text=True,
    stdout=subprocess.PIPE,
    check=False,
).stdout.splitlines()
for row in rows:
    parts = row.split(':')
    if len(parts) < 2:
        continue
    name, device = parts[0], parts[-1]
    if device in targets:
        subprocess.run(['sudo', '-n', 'nmcli', 'con', 'delete', name], check=False)
PY"
  done
}

set_network() {
  local args=()
  local row alias path
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    alias="${row%%=*}"
    path="${row#*=}"
    args+=("$alias:$path")
  done < "$RUN_DIR/netplan-paths.txt"
  [[ "${#args[@]}" -gt 0 ]] || die "no netplan paths found; run detect first"
  password_stdin | nvsync_cmd integration spark set-network "${args[@]}" --password-stdin \
    | tee "$RUN_DIR/set-network.jsonl"
}

verify() {
  read_aliases
  ensure_run_dir
  latest_link
  if ! resolve_artifact_run_dir "verify-config.json"; then
    log "no saved verify-config.json found; generating a live snapshot first"
    snapshot_live
  fi
  nvsync_cmd integration spark verify-network "${ALIAS_ARRAY[@]}" --config-stdin \
    < "$RUN_DIR/verify-config.json" | tee "$RUN_DIR/verify-network.jsonl"
}

cluster_ssh() {
  read_aliases
  ensure_run_dir
  latest_link
  resolve_artifact_run_dir "cluster-ssh-commands.txt" \
    || die "missing cluster-ssh-commands.txt; run detect/snapshot-live/configure first"
  local cmd_args
  while IFS= read -r cmd; do
    [[ -n "$cmd" ]] || continue
    log "running: $cmd"
    # Split the command line into an args array (avoids SC2086 unquoted
    # expansion while preserving intentional word-splitting into arguments).
    read -r -a cmd_args <<< "$cmd"
    nvsync_cmd integration spark setup-cluster-ssh "${cmd_args[@]}" | tee -a "$RUN_DIR/setup-cluster-ssh.jsonl"
  done < "$RUN_DIR/cluster-ssh-commands.txt"
}

nvsync_test() {
  read_aliases
  # No `|| true`: with `set -o pipefail`, a fabric-test failure must propagate so
  # `configure` returns non-zero. Use `--skip-nvsync-test` to bypass intentionally.
  nvsync_cmd integration spark test-network "$TOPOLOGY" "${ALIAS_ARRAY[@]}" --config-stdin \
    < "$RUN_DIR/verify-config.json" | tee "$RUN_DIR/test-network.jsonl"
}

cleanup_tests() {
  read_aliases
  ensure_run_dir
  latest_link
  local alias
  for alias in "${ALIAS_ARRAY[@]}"; do
    log "killing stale perftest/iperf on $alias"
    remote "$alias" "pkill -9 -x ib_write_bw 2>/dev/null || true; pkill -9 -x ib_read_bw 2>/dev/null || true; pkill -9 -x ib_send_bw 2>/dev/null || true; pkill -9 -x ib_write_lat 2>/dev/null || true; pkill -9 -x iperf3 2>/dev/null || true"
  done
}

rdma_test() {
  read_aliases
  ensure_run_dir
  latest_link
  resolve_artifact_run_dir "rdma-tests.tsv" \
    || die "missing rdma-tests.tsv; run detect/snapshot-live/configure first"
  cleanup_tests
  local row local_alias remote_alias device gid_index remote_gid_or_target target_ip_or_port port
  local local_gid_index remote_gid_index target_ip
  local failed=0
  local client_rc server_rc
  while IFS=$'\t' read -r local_alias remote_alias device gid_index remote_gid_or_target target_ip_or_port port; do
    [[ "$local_alias" == "local_alias" || -z "$local_alias" ]] && continue
    if [[ -n "${port:-}" ]]; then
      local_gid_index="$gid_index"
      remote_gid_index="$remote_gid_or_target"
      target_ip="$target_ip_or_port"
    else
      local_gid_index="$gid_index"
      remote_gid_index="$gid_index"
      target_ip="$remote_gid_or_target"
      port="$target_ip_or_port"
    fi
    log "RDMA test $device $local_alias(gid=$local_gid_index) -> $target_ip $remote_alias(gid=$remote_gid_index)"
    remote "$remote_alias" "timeout 25 ib_write_bw -d '$device' --gid-index='$remote_gid_index' -p '$port' --report_gbits" \
      < /dev/null > "$RUN_DIR/rdma-server-$device.log" 2>&1 &
    local server_pid=$!
    sleep 1
    # Capture the client's ib_write_bw exit code: ${PIPESTATUS[0]} is the test,
    # not tee. Without this the `| tee` (and any `|| true`) would swallow failures
    # and let a broken RoCE path report success.
    client_rc=0
    remote "$local_alias" "timeout 20 ib_write_bw -d '$device' --gid-index='$local_gid_index' -p '$port' --report_gbits '$target_ip'" \
      < /dev/null 2>&1 | tee "$RUN_DIR/rdma-client-$device.log"
    client_rc=${PIPESTATUS[0]}
    server_rc=0
    wait "$server_pid" || server_rc=$?
    if [[ "$client_rc" -ne 0 || "$server_rc" -ne 0 ]]; then
      failed=1
      log "RDMA test FAILED for $device (client_rc=$client_rc server_rc=$server_rc)"
    fi
  done < "$RUN_DIR/rdma-tests.tsv"
  cleanup_tests
  if [[ "$failed" -ne 0 ]]; then
    die "one or more RDMA bandwidth tests failed; see $RUN_DIR/rdma-*.log"
  fi
}

configure() {
  [[ "$APPLY" -eq 1 ]] || die "configure requires --apply"
  read_aliases
  ensure_run_dir
  latest_link
  preflight
  detect
  backup_netplan
  if [[ "$CLEAN_CONFLICTS" -eq 1 ]]; then
    clean_conflicts
  fi
  set_network
  verify
  if [[ "$SETUP_CLUSTER_SSH" -eq 1 ]]; then
    cluster_ssh
  fi
  if [[ "$SKIP_NVSYNC_TEST" -eq 0 ]]; then
    nvsync_test
  fi
}

recover() {
  cleanup_tests
  verify || true
  cat <<EOF
Rollback guidance:
  - NVIDIA Sync delete-cluster removes node-to-node SSH but does not remove netplan.
  - To remove cluster networking on a node:
      sudo mkdir -p /root/netplan-disabled
      sudo mv /etc/netplan/99-nvidia-sync-cluster.yaml /root/netplan-disabled/
      sudo netplan generate
      sudo netplan try
  - Backups from this run are listed in $RUN_DIR/netplan-backups.txt when configure was used.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

COMMAND="${1:-}"
[[ -n "$COMMAND" ]] || { usage; exit 2; }
shift || true

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --aliases) ALIASES="${2:?--aliases requires a value}"; shift ;;
    --ip-base) IP_BASE="${2:?--ip-base requires a value}"; shift ;;
    --apply) APPLY=1 ;;
    --clean-conflicts) CLEAN_CONFLICTS=1 ;;
    --cluster-ssh) SETUP_CLUSTER_SSH=1 ;;
    --skip-nvsync-test) SKIP_NVSYNC_TEST=1 ;;
    --verbose) VERBOSE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

need_cmd python3
need_cmd ssh
[[ -x "$NVSYNC" ]] || die "missing executable nvsync helper: $NVSYNC"

case "$COMMAND" in
  doctor) doctor ;;
  preflight) preflight ;;
  detect) detect ;;
  snapshot-live) snapshot_live ;;
  configure) configure ;;
  verify) verify ;;
  cluster-ssh) cluster_ssh ;;
  rdma-test) rdma_test ;;
  cleanup-tests) cleanup_tests ;;
  recover) recover ;;
  *) usage; die "unknown command: $COMMAND" ;;
esac
