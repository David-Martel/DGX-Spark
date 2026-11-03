# Build and validate DGX Spark tooling

Start with the four commands in the [README](../README.md#install-build-test-run).
Run them from the repository root. The [GB10 recipes](../gb10-cuda/justfile)
invoke scripts relative to the justfile directory.

## Prerequisites and build scope

Install `just` before using the quick start; its test command needs Bash, Python 3,
`uv` and standard Linux command-line utilities. Install, build and inventory
target a DGX Spark: Linux aarch64, NVIDIA drivers and the system CUDA toolchain.
The install recipe provisions system dependencies and needs `sudo`, package and
network access. Review the [dependency installer](../gb10-cuda/scripts/install_deps.sh)
before running it. Its existing TensorRT dry-run pipeline can enter the install
branch when the simulation fails; inspect the proposed package changes before
using this installer on a managed driver/CUDA baseline. This documentation
change does not repair or qualify that installer.

The build line runs only the [FFmpeg builder](../gb10-cuda/scripts/build_ffmpeg.sh).
It needs CUDA and the installed build dependencies, downloads source and writes
under `/opt/gb10-cuda` by default. It is not an OpenCV or inference-stack build.

The separate [OpenCV builder](../gb10-cuda/scripts/build_opencv.sh) requires official
Video Codec SDK headers under `/opt/gb10-cuda/install/video-codec-sdk/include`
by default. The [gated SDK downloader](../gb10-cuda/scripts/download_nvidia_gated_sdks_with_bw.sh),
exposed as `just -f gb10-cuda/justfile download-gated-sdks`, needs the appropriate
NVIDIA download access and an unlocked Bitwarden session, or an official SDK
archive staged under `/opt/gb10-cuda/sdks`. Do not publish credentials or archives.
It also requires `bw`, `jq`, `curl` and `unzip`, installs headers into the CUDA
include directory, and can exit zero after skipping a download. Check its report
and the required header files before starting OpenCV.
FFmpeg's codec headers do not satisfy this separate OpenCV prerequisite.

Set `OPENCV_PYTHON` to the intended interpreter, or prepare the expected
`/opt/gb10-cuda/venvs/media/bin/python` before building OpenCV. Otherwise the
builder falls back to `/usr/bin/python3` and targets its package directory;
the Python binding can therefore install outside `/opt/gb10-cuda` or fail on
permissions. The quick start does not take this path.

The optional [managed-Python installer](../gb10-cuda/scripts/install_uv_python.sh)
bootstraps `uv` through a downloaded shell script when it is absent. It attempts
to make a beta Python the default uv-managed interpreter, installs a stable
fallback, and recreates its smoke virtual environment. Review its current pins
and shim/PATH effects first; it does not create the OpenCV media virtual environment.

The [inventory script](../gb10-cuda/scripts/inventory.sh) writes
a host report under `$HOME/gb10-cuda/reports` by default. Its shared setup also
creates build directories and recursively changes ownership of all existing
contents under `/opt/gb10-cuda` through `sudo`. It compiles `/tmp/cuda_um_probe`
and runs it; inventory is not a read-only host query. Individual section failures
are tolerated, so exit zero does not prove CUDA or any other section succeeded;
read the report contents.
Generated reports can contain host identifiers; follow the
[publication guidance](../README.md#public-repo-hygiene).

## Software checks

The [lint workflow](../.github/workflows/lint.yml) has two independent jobs.
The quick-start test line uses the workflow's tracked-file selection for Ruff,
then runs both existing local regression scripts. `uvx` may download Ruff; use the
same tool version when comparing a local result with a particular CI run.

Run the ShellCheck job separately from the repository root with Bash and
ShellCheck installed:

```bash
mapfile -d '' scripts < <(find . -name '*.sh' -not -path './external/*' -not -path './.git/*' -print0)
shellcheck --severity=warning "${scripts[@]}"
```

The workflow excludes the vendor submodule. Keep linked worktrees out of this
checkout while running that exact `find` command: the workflow does not exclude
`worktrees/`. Neither lint job compiles the SDK, builds CUDA media libraries or
opens a camera.

Two existing mocked regression scripts can run on Linux without a Spark:

```bash
bash gb10-cuda/test/test_accel_install_fail_closed.sh
bash qsfp-cluster/test/test_portable_commands.sh
```

The [installer test](../gb10-cuda/test/test_accel_install_fail_closed.sh) detects
provisioning before prerequisite admission using mocked commands, including a
positive control that reaches provisioning. The
[portable-command test](../qsfp-cluster/test/test_portable_commands.sh) checks
local doctor/verify behavior and refusal when the NVIDIA Sync helper is missing.
Its missing-helper diagnostics are intentional. These scripts are separate local
checks; the lint workflow does not execute them.

## Validation limits

A lint or mocked-test pass establishes only the software behavior that check
exercises. Install, native build, camera capture, network configuration, RDMA,
VIGIL runtime performance and operator acceptance each need their own evidence.
Record the source revision, host, dependencies, selected device or topology,
command, criteria, result and teardown for a hardware run. Preserve a failed or
missing prerequisite as a failure or `NOT_RUN`, respectively.

Use the [QSFP guide](../qsfp-cluster/README.md) for topology-specific preflight,
configuration and rollback. Use the [RealSense findings](GB10_REALSENSE_FINDINGS.md)
and [GB10 backlog](../gb10-cuda/TODO.md) for historical findings and outstanding
work. Their earlier observations do not establish the state of a current host.
