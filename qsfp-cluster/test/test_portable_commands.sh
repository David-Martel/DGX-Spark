#!/usr/bin/env bash
set -Eeuo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QSFP_ROOT="$(cd "$TEST_DIR/.." && pwd)"
SCRIPT="$QSFP_ROOT/bin/spark_qsfp_cluster.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

MOCK_BIN="$TMP_ROOT/bin"
ARTIFACT_ROOT="$TMP_ROOT/artifacts"
mkdir -p "$MOCK_BIN" "$ARTIFACT_ROOT/portable-test"

cat > "$MOCK_BIN/ssh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-G" ]]; then
  printf 'host %s\nhostname %s\nuser tester\n' "${2:-unknown}" "${2:-unknown}"
fi
exit 0
EOF

cat > "$MOCK_BIN/ip" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "-o -4 addr show" ]]; then
  printf '7: enp1s0f0np0    inet 10.55.0.1/30 scope global enp1s0f0np0\n'
else
  printf 'enp1s0f0np0 UP 10.55.0.1/30\n'
fi
EOF

cat > "$MOCK_BIN/ping" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "$MOCK_BIN/timeout" <<'EOF'
#!/usr/bin/env bash
shift
"$@"
EOF

cat > "$MOCK_BIN/hostname" <<'EOF'
#!/usr/bin/env bash
printf 'spark-test\n'
EOF

chmod +x "$MOCK_BIN"/*

cat > "$ARTIFACT_ROOT/portable-test/verify-config.json" <<'EOF'
{
  "spark-test": {
    "expected_ips": {"enp1s0f0np0": "10.55.0.1/30"},
    "ping_targets": ["10.55.0.2"]
  }
}
EOF

run_portable() {
  PATH="$MOCK_BIN:$PATH" \
    SPARK_QSFP_ALIASES="spark-test peer-test" \
    SPARK_QSFP_NVSYNC="$TMP_ROOT/missing-nvsync" \
    SPARK_QSFP_ARTIFACT_ROOT="$ARTIFACT_ROOT" \
    SPARK_QSFP_RUN_ID="portable-test" \
    "$SCRIPT" "$@"
}

doctor_output="$(run_portable doctor)"
grep -Fq 'missing' <<< "$doctor_output"

verify_output="$(run_portable verify)"
grep -Fq 'running local IP+ping verification' <<< "$verify_output"
grep -Fq '"event": "expected_ip"' <<< "$verify_output"
grep -Fq '"result": "PASS"' <<< "$verify_output"

if run_portable preflight > "$TMP_ROOT/preflight.log" 2>&1; then
  echo 'preflight unexpectedly succeeded without nvsync' >&2
  exit 1
fi
grep -Fq 'missing executable nvsync helper' "$TMP_ROOT/preflight.log"

printf 'portable command regression checks passed\n'
