# Build and validate DGX Spark tooling

Start with the four commands in the [README](../README.md#install-build-test-run).
Run them from the repository root. The [GB10 recipes](../gb10-cuda/justfile)
invoke scripts relative to the justfile directory.

## Prerequisites and build scope

Install `just` before using the quick start; the Ruff command also needs `uv`.
The Python installer can bootstrap `uv` if it is missing. Install, build and inventory
target a DGX Spark: Linux aarch64, NVIDIA drivers and the system CUDA toolchain.
The install recipes provision system dependencies and a managed Python; they
need `sudo`; installation also needs package and network access. Review the
[dependency installer](../gb10-cuda/scripts/install_deps.sh) and
[Python installer](../gb10-cuda/scripts/install_uv_python.sh) before running them.

The build line runs the [FFmpeg builder](../gb10-cuda/scripts/build_ffmpeg.sh)
and [OpenCV builder](../gb10-cuda/scripts/build_opencv.sh). Their prerequisites
include CUDA and the installed build dependencies. They download source and write
under `/opt/gb10-cuda` by default; the command is not a full inference-stack
installation. The [inventory script](../gb10-cuda/scripts/inventory.sh) writes
a host report under `$HOME/gb10-cuda/reports` by default. Its shared setup also
creates and changes ownership of the `/opt/gb10-cuda` directories through `sudo`,
and it compiles and runs a CUDA probe; inventory is not a read-only host query.
Generated reports can contain host identifiers; follow the
[publication guidance](../README.md#public-repo-hygiene).

## Software checks

The [lint workflow](../.github/workflows/lint.yml) has two independent jobs.
The quick-start test line runs its Ruff check and format check over the two
tracked Python files under `qsfp-cluster/lib/`. `uvx` may download Ruff; use the
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
