#!/usr/bin/env bash
# Regression checks for the fail-closed preflight in install_inference_accel_stack.sh.
#
# Runs the real installer against mocked uv/sudo/dpkg-query and a fake
# CUDA_HOME, so no GB10 host is needed. The discriminator is the uv call log,
# not the exit status: pre-fix, the installer still died eventually (in the
# validator), so "exits non-zero" alone was green before and after the fix.
# What fail-closed means is that uv is never invoked at all.
#
# Usage: test_accel_install_fail_closed.sh [scripts-dir]
set -Eeuo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${1:-$TEST_DIR/../scripts}" && pwd)"
INSTALLER="$SCRIPTS_DIR/install_inference_accel_stack.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

MOCK_BIN="$TMP_ROOT/bin"
mkdir -p "$MOCK_BIN"

cat > "$MOCK_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF

# Every uv call is recorded. `uv venv` then fails, so a run that gets past the
# preflight stops there instead of reaching the real validator.
cat > "$MOCK_BIN/uv" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$UV_CALL_LOG"
[[ "${1:-}" == "venv" ]] && exit 1
exit 0
EOF

cat > "$MOCK_BIN/dpkg-query" <<'EOF'
#!/usr/bin/env bash
[[ -n "${MOCK_LIBNVINFER_VERSION:-}" ]] || exit 1
printf '%s' "$MOCK_LIBNVINFER_VERSION"
EOF

chmod +x "$MOCK_BIN"/*

make_cuda() {
  local dir="$TMP_ROOT/cuda-$1"
  mkdir -p "$dir/bin"
  cat > "$dir/bin/nvcc" <<EOF
#!/usr/bin/env bash
printf 'Cuda compilation tools, release $1, V$1.0\n'
EOF
  chmod +x "$dir/bin/nvcc"
  printf '%s\n' "$dir"
}

CUDA_OK="$(make_cuda 13.2)"
CUDA_OLD="$(make_cuda 12.8)"
CUDA_MISSING="$TMP_ROOT/cuda-missing"
mkdir -p "$CUDA_MISSING"

failures=0
case_no=0

# run_case NAME CUDA_HOME LIBNVINFER_VERSION EXPECT(uv-called|uv-not-called) EXPECT_TEXT
run_case() {
  local name="$1" cuda_home="$2" libnvinfer="$3" expect="$4" expect_text="$5"
  case_no=$((case_no + 1))
  local dir="$TMP_ROOT/case-$case_no" status=0
  mkdir -p "$dir"
  : > "$dir/uv-calls"
  PATH="$MOCK_BIN:$PATH" \
    GB10_ROOT="$dir/root" \
    GB10_HOME="$dir/home" \
    CUDA_HOME="$cuda_home" \
    UV_CALL_LOG="$dir/uv-calls" \
    MOCK_LIBNVINFER_VERSION="$libnvinfer" \
    "$INSTALLER" > "$dir/output.log" 2>&1 || status=$?

  local ok=1
  if [[ "$status" -eq 0 ]]; then
    echo "  $name: installer exited 0; every case here must stop early" >&2
    ok=0
  fi
  if [[ "$expect" == uv-not-called && -s "$dir/uv-calls" ]]; then
    echo "  $name: uv was invoked, so provisioning began:" >&2
    sed 's/^/    uv /' "$dir/uv-calls" >&2
    ok=0
  fi
  if [[ "$expect" == uv-called && ! -s "$dir/uv-calls" ]]; then
    echo "  $name: uv was never invoked; the preflight refused a valid host" >&2
    ok=0
  fi
  if ! grep -Fq -- "$expect_text" "$dir/output.log"; then
    echo "  $name: output lacks '$expect_text'" >&2
    ok=0
  fi
  if [[ "$ok" -eq 1 ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (exit %s)\n' "$name" "$status"
    sed 's/^/    | /' "$dir/output.log"
    failures=$((failures + 1))
  fi
}

# Positive control: prerequisites satisfied, so the preflight passes, the CUDA
# check reports itself, and provisioning reaches uv.
run_case "prerequisites present -> provisioning starts" \
  "$CUDA_OK" "11.2.1.2-1+cuda13.3" uv-called "gb10: system CUDA 13.2"

run_case "libnvinfer-bin absent -> abort before uv" \
  "$CUDA_OK" "" uv-not-called "cannot derive the TensorRT pin"

run_case "no nvcc in CUDA_HOME -> abort before uv" \
  "$CUDA_MISSING" "11.2.1.2-1+cuda13.3" uv-not-called "no nvcc at $CUDA_MISSING/bin/nvcc"

run_case "system CUDA older than 13.2 -> abort before uv" \
  "$CUDA_OLD" "11.2.1.2-1+cuda13.3" uv-not-called "system CUDA 12.8 at $CUDA_OLD is older than the required 13.2"

if [[ "$failures" -ne 0 ]]; then
  printf '%d of %d fail-closed checks failed\n' "$failures" "$case_no" >&2
  exit 1
fi
printf 'accel install fail-closed checks passed (%d cases)\n' "$case_no"
