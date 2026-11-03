# DGX Spark

Public development point for DGX Spark / GB10 platform enablement, CUDA media
and AI tooling, and machine-specific optimization work that can be reused across
projects.

## Install, build, test, run

Run these commands from the repository root after [cloning](#clone). Install,
build and run require a DGX Spark with its NVIDIA drivers and use `sudo`.
The test command runs the Ruff job from the [lint workflow](.github/workflows/lint.yml)
and the two existing mocked regression scripts.

```bash
# Install (DGX Spark)
just -f gb10-cuda/justfile install-deps
# Build FFmpeg (DGX Spark; OpenCV has separate SDK prerequisites)
just -f gb10-cuda/justfile build-ffmpeg
# Test (CI Ruff job plus local regressions; Linux with uv and Python 3)
bash -c 'set -euo pipefail
mapfile -d "" pyfiles < <(git ls-files -z -- "*.py" | grep -zv "^external/")
test "${#pyfiles[@]}" -gt 0
uvx ruff check "${pyfiles[@]}"
uvx ruff format --check "${pyfiles[@]}"
bash gb10-cuda/test/test_accel_install_fail_closed.sh
bash qsfp-cluster/test/test_portable_commands.sh'
# Run (DGX Spark; writes an inventory report)
just -f gb10-cuda/justfile inventory
```

The [build and validation guide](docs/build-test-run.md) explains prerequisites,
the separate ShellCheck job, mocked regression tests and hardware evidence limits.

This repository has three surfaces:

- `gb10-cuda/` - reusable FFmpeg, OpenCV, CUDA, Python, Triton, TensorRT, and
  NVIDIA media-tooling scripts developed on the DGX Spark host.
- `qsfp-cluster/` - NVIDIA Sync-backed QSFP/ConnectX-7 detection,
  configuration, verification, and RDMA validation for multi-Spark clusters.
- `external/librealsense/` - Git submodule pointing at
  `David-Martel/librealsense` for RealSense customizations.

## Clone

```bash
git clone --recurse-submodules https://github.com/David-Martel/DGX-Spark.git
cd DGX-Spark
```

If the repository is already cloned:

```bash
git submodule update --init --recursive
```

## GB10 CUDA Framework

The `gb10-cuda` subproject is designed to install into `/opt/gb10-cuda` while
keeping Ubuntu, NVIDIA driver packages, ROS, and `/usr/bin/python3` intact.

```bash
cd gb10-cuda
just --list
```

Key targets:

```bash
just inventory
just install-deps
just install-uv-python
just install-extended-toolsets
just build-ffmpeg
just build-opencv
just install-triton-stack
just validate-triton-stack
just install-inference-accel-stack
just validate-inference-accel-stack
just audit-torch-envs
just benchmark
just debug-report
```

Read [the GB10 backlog](gb10-cuda/TODO.md) for the recorded validation and remaining gap
work. Generated reports are intentionally ignored by Git; publish only sanitized
summaries.

## QSFP / ConnectX-7 Cluster Automation

Use `qsfp-cluster/bin/spark_qsfp_cluster.sh` to wrap NVIDIA Sync Cluster
Assistant with repeatable preflight, detection, Netplan backups, conflict
cleanup, verification, and RDMA checks:

```bash
./qsfp-cluster/bin/spark_qsfp_cluster.sh doctor
./qsfp-cluster/bin/spark_qsfp_cluster.sh detect
./qsfp-cluster/bin/spark_qsfp_cluster.sh configure --apply --clean-conflicts --cluster-ssh
./qsfp-cluster/bin/spark_qsfp_cluster.sh verify
./qsfp-cluster/bin/spark_qsfp_cluster.sh rdma-test
```

See [`qsfp-cluster/README.md`](qsfp-cluster/README.md) for the supported
NVIDIA topology model, alias conventions, reboot recovery, rollback guidance,
and VIGIL/NCCL environment variables.

RealSense (D400) GPU-acceleration + USB-controller hardening findings on GB10 are
summarized in [`docs/GB10_REALSENSE_FINDINGS.md`](docs/GB10_REALSENSE_FINDINGS.md);
full HIL detail lives in the `external/librealsense` submodule under `docs/gb10/`.

## Public-Repo Hygiene

Do not commit:

- Bitwarden sessions, NGC tokens, cookies, or downloaded gated SDK archives.
- Generated reports containing hostnames, usernames, UUIDs, or local inventory.
- `/opt/gb10-cuda` build trees, logs, venvs, SDK extracts, or model artifacts.
- Large model weights, media corpora, or benchmark inputs unless they are
  explicitly public and licensed for redistribution.

## Platform history

Earlier GB10 development notes reported the capabilities below. Recheck the
current host before relying on them; this list does not qualify an installation
or the VIGIL application. See the [validation limits](docs/build-test-run.md#validation-limits).

- CUDA 13 GB10 media stack
- FFmpeg with CUDA/NVENC/NVDEC
- OpenCV 4.14 pre-release with CUDA, cuDNN, cudacodec, FFmpeg, GStreamer, TBB
- uv-managed Python 3.14 media venv with CuPy, Torch CUDA 13, Triton, OpenCV,
  and nvImageCodec
- Python 3.13 compatibility venv for PyNvVideoCodec
- NVIDIA Triton Inference Server Arm container smoke
- TensorRT/ONNX system Python bindings
- uv-managed inference acceleration lane for ONNX, ONNXScript, TensorRT Python
  wheels, Torch-TensorRT import validation, and FlashAttention smoke checks
- Riva client package import path

The remaining work is tracked in [the GB10 backlog](gb10-cuda/TODO.md).
