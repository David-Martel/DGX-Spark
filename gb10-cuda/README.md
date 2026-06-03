# GB10 CUDA Media Acceleration

This workspace builds and validates a DGX Spark / GB10 optimized FFmpeg,
OpenCV, and Python GPU media stack without replacing the distro OpenCV or
system CUDA baseline.

## Layout

- `justfile` - operator command surface
- `scripts/` - idempotent install/build/validate/benchmark scripts
- `reports/` - inventory, validation, benchmark, and debug reports
- `/opt/gb10-cuda/src` - cloned upstream sources
- `/opt/gb10-cuda/build` - build trees
- `/opt/gb10-cuda/install` - optimized install prefixes
- `/opt/gb10-cuda/state` - state markers
- `/opt/gb10-cuda/logs` - command logs
- `/opt/gb10-cuda/venvs` - isolated Python environments

## Common Commands

```bash
cd ~/gb10-cuda
just inventory
just install-deps
just install-uv-python
just install-extended-toolsets
just download-sdks
just validate-toolsets
just build-ffmpeg
just validate-ffmpeg
just build-opencv
just validate-opencv
just install-triton-stack
just validate-triton-stack
just benchmark
just debug-report
```

Use `FORCE_REBUILD=1` with build commands to wipe and rebuild a component.

## Installed Stack

- Optimized FFmpeg: `/opt/gb10-cuda/install/ffmpeg`
- Optimized OpenCV: `/opt/gb10-cuda/install/opencv`
- Official Video Codec SDK headers:
  `/opt/gb10-cuda/install/video-codec-sdk/include`
- CUDA target headers, including official NVENC/NVDEC headers:
  `/usr/local/cuda/targets/sbsa-linux/include`
- Primary uv media venv: `/opt/gb10-cuda/venvs/media`
- PyNvVideoCodec compatibility venv:
  `/opt/gb10-cuda/venvs/media-cpython-3.13.13`
- Riva client/audio venv:
  `/opt/gb10-cuda/venvs/audio-cpython-3.13.13`
- Triton model repository root:
  `/opt/gb10-cuda/triton/model_repository`
- Triton Server image:
  `nvcr.io/nvidia/tritonserver:25.12-py3`

For OpenCV/CuPy/nvImageCodec work:

```bash
source /opt/gb10-cuda/venvs/media/bin/activate
export LD_LIBRARY_PATH=/opt/gb10-cuda/install/opencv/lib:/opt/gb10-cuda/install/ffmpeg/lib:/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}
python -c 'import cv2; print(cv2.__version__, cv2.cuda.getCudaEnabledDeviceCount())'
```

For PyNvVideoCodec work:

```bash
source /opt/gb10-cuda/venvs/media-cpython-3.13.13/bin/activate
python -c 'import PyNvVideoCodec; print(PyNvVideoCodec.__version__)'
```

For Riva client work:

```bash
source /opt/gb10-cuda/venvs/audio-cpython-3.13.13/bin/activate
python -c 'import riva.client; print(riva.client.__version__)'
```

For Triton Python compiler work:

```bash
source /opt/gb10-cuda/venvs/media/bin/activate
python -c 'import torch, triton; print(torch.__version__, triton.__version__, torch.cuda.get_device_name(0))'
```

For Triton Server smoke validation:

```bash
cd ~/gb10-cuda
just validate-triton-stack
```

## Python Policy

`uv` is installed under `~/.local/bin` and manages the workspace Python
versions. Python 3.15.0b1 is installed as the uv default, but CUDA media wheels
are not fully available for `cp315` yet. Use Python 3.14 for OpenCV/CuPy and
Python 3.13 for PyNvVideoCodec until those wheels catch up.

The distro `/usr/bin/python3` remains unchanged for apt, ROS, NVIDIA packages,
and desktop tooling. TensorRT and ONNX Python bindings are installed through
apt for `/usr/bin/python3` because NVIDIA ships those bindings as distro
packages on this host.

## Validation Evidence

- Inventory: `reports/inventory-20260603T120628Z.md`
- FFmpeg validation: `reports/validate-ffmpeg-20260603T121328Z.md`
- uv Python setup: `reports/uv-python-20260603T122315Z.md`
- Official Video Codec SDK install:
  `reports/nvidia-gated-sdk-downloads-20260603T125100Z.md`
- Toolset validation: `reports/validate-toolsets-20260603T130705Z.md`
- OpenCV CUDA validation: `reports/validate-opencv-20260603T132542Z.md`
- Python GPU stack validation:
  `reports/validate-python-stack-20260603T132426Z.md`
- Triton install: `reports/install-triton-stack-20260603T132242Z.md`
- Triton validation: `reports/validate-triton-stack-20260603T132408Z.md`
- AI/audio validation: `reports/validate-ai-audio-stack-20260603T131216Z.md`
- Benchmark: `reports/benchmark-20260603T131127Z.md`
- Benchmark dmon: `reports/benchmark-dmon-20260603T131127Z.log`
- Debug capture: `reports/debug-20260603T132557Z.md`

Current benchmark snapshot:

- System FFmpeg software scale: 0.604211 seconds
- Optimized FFmpeg CUDA scale plus NVENC: 1.42154 seconds
- OpenCV CPU resize plus color conversion: 0.067877713 seconds
- OpenCV CUDA resize plus color conversion: 0.102567829 seconds

NVIDIA Container Toolkit is installed and `sudo docker --gpus all` sees the
GB10 GPU. The current user is not in the Docker access path for
`/var/run/docker.sock`, so Docker GPU validation is recorded through sudo.

Triton is installed in both useful forms: `torch 2.12.0+cu130` plus
`triton 3.7.0` in the primary uv media venv for custom kernel work, and
NVIDIA Triton Inference Server 2.64.0 via the official Arm container image.

These synthetic microbenchmarks validate functionality and expose transfer
overhead. They are not a final throughput model for longer pipelines that keep
frames resident on GPU.

## Rollback

The optimized stack is isolated. To stop using it, remove references to
`/opt/gb10-cuda/install/*/bin` and deactivate any venvs under
`/opt/gb10-cuda/venvs`.

Full removal is intentionally gated:

```bash
cd ~/gb10-cuda
ALLOW_PURGE_GB10_CUDA=1 just purge-install
```

`uv` managed Python is used for this workspace. The distro
`/usr/bin/python3` is intentionally left unchanged.
