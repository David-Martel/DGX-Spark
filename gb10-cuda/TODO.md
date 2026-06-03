# GB10 CUDA Media Acceleration TODO

Purpose: build, validate, and document a DGX Spark / GB10 optimized media and
computer-vision stack for this machine.

Platform assumptions verified on 2026-06-03:

- Ubuntu 24.04.4 LTS on `aarch64`
- NVIDIA GB10 Blackwell, CUDA compute capability `12.1`
- NVIDIA driver `580.159.03`
- CUDA Toolkit `13.0.x`
- CUDA unified-memory probe: `pageableMemoryAccess=1`,
  `pageableUsesHostPT=1`, `concurrentManagedAccess=1`
- Stock OpenCV is Ubuntu `4.6.0` with FFmpeg/GStreamer I/O but without CUDA
  modules
- Stock `ffmpeg` CLI was absent at initial inventory

## Rules

- Keep the distro stack intact; install optimized builds into
  `/opt/gb10-cuda/install`.
- Keep sources, build trees, logs, state markers, and benchmarks under
  `/opt/gb10-cuda`.
- Keep operator-facing docs and scripts under `~/gb10-cuda`.
- All scripts must be idempotent: rerunning should either reuse existing
  artifacts or rebuild only when explicitly requested.
- Every install/build step must emit logs and a validation artifact.
- Benchmarks must compare the system baseline against the optimized path where
  possible.
- Prefer NVIDIA package repositories and official upstream source builds.
- For DGX Spark UMA, do not rely only on `cudaMemGetInfo`; also record
  `/proc/meminfo` and CUDA device attributes.

## Checklist

### 0. Harness and Documentation

- [x] Create `gb10-cuda.TODO.md` with task checklist and validation standards.
- [x] Create `gb10-cuda/justfile` as the command surface.
- [x] Create robust shell scripts with shared logging, state markers, and
  explicit install prefixes.
- [x] Generate first inventory report under `gb10-cuda/reports/`.
- [x] Keep `gb10-cuda/README.md` current with installed prefixes, usage, and
  rollback notes.

### 1. Baseline Inventory

- [x] Capture OS, kernel, CPU, memory, disk, compiler, Python, and package state.
- [x] Capture NVIDIA driver, GPU, topology, encoder/decoder/JPEG utilization,
  and running GPU processes.
- [x] Compile and run a CUDA GB10 capability probe.
- [x] Capture stock Python OpenCV build information.
- [x] Capture FFmpeg and GStreamer baseline capabilities.
- [x] Save all reports in `gb10-cuda/reports/inventory-*`.

### 2. System Dependencies and SDKs

- [x] Install missing build tools: `just`, `yasm`, `nasm`, CMake/Ninja deps,
  codec dev packages, GTK/TBB/OpenBLAS/Python dev packages.
- [x] Install stock FFmpeg and GStreamer plugin baseline packages.
- [x] Install CUDA media/inference SDK packages:
  `libcudnn9-cuda-13`, `libcudnn9-dev-cuda-13`,
  `libcudnn9-jit-cuda-13`, `libcudnn9-jit-dev-cuda-13`,
  `libnvjpeg2k0-dev-cuda-13`, `libnvjpeg2k0-static-cuda-13`.
- [x] Install TensorRT packages only after an apt dry-run confirms no unwanted
  driver or CUDA baseline replacement.
- [x] Validate package installs with `dpkg-query`, `ldconfig -p`, `nvcc`, and
  sample header/library lookups.

### 2A. Extended NVIDIA and ARM Acceleration Toolsets

- [x] Install CUDA compile/runtime tools not present in the base toolkit:
  `cuda-ctadvisor-13-0`, `cuda-sandbox-dev-13-0`, and CUDA samples.
- [x] Install ML math libraries: NCCL, cuTENSOR, cuSPARSELt, and cuDSS for
  CUDA 13.
- [x] Install NVIDIA HPC SDK for Arm (`nvhpc-26-3`) and record compiler paths.
- [x] Install Holoscan CUDA 13 for sensor/medical streaming pipelines.
- [x] Install Vulkan tools and validation layers for Vulkan interop paths.
- [x] Install CPU-side optimization helpers: Taskflow, tcmalloc, and benchmark
  tooling.
- [x] Download/probe NVIDIA Video Codec SDK interface/full SDK. Official SDK
  archive found at `~/Downloads/Video_Codec_SDK_13.0.37.zip`; headers installed
  into `/opt/gb10-cuda/install/video-codec-sdk/include` and
  `/usr/local/cuda/targets/sbsa-linux/include`.
- [x] Download/probe NVIDIA Optical Flow SDK. Driver library
  `libnvidia-opticalflow.so` is present; no separate Linux SBSA Optical Flow SDK
  archive was found in `~/Downloads`.
- [x] Validate headers/libraries for NVENC, NVDEC, NVOFA, cuDNN, TensorRT,
  NCCL, cuTENSOR, cuSPARSELt, cuDSS, Holoscan, and HPC SDK.

### 2B. uv Python Runtime

- [x] Install/update `uv` from the official standalone installer when needed.
- [x] Install uv-managed `cpython-3.15.0b1-linux-aarch64-gnu` and make it the
  user/project default via uv.
- [x] Install uv-managed `cpython-3.14.5-linux-aarch64-gnu` as the stable wheel
  compatibility fallback.
- [x] Do not replace `/usr/bin/python3`; keep Ubuntu system Python intact for
  apt, ROS, NVIDIA packages, and desktop tooling.
- [x] Use uv-managed Python for GB10 media/AI virtual environments.
- [x] Validate `uv python list`, `python --version`, and venv creation.

### 3. NVIDIA FFmpeg Build

- [x] Clone/update `nv-codec-headers`.
- [x] Clone/update FFmpeg source.
- [x] Build FFmpeg with CUDA/NVENC/NVDEC support into
  `/opt/gb10-cuda/install/ffmpeg`.
- [x] Validate `ffmpeg -hwaccels` includes CUDA.
- [x] Validate `ffmpeg -encoders` exposes NVENC encoders.
- [x] Validate `ffmpeg -filters` exposes CUDA filters where available.
- [x] Run a generated-video smoke transcode through NVENC.
- [x] Run decode/scale benchmark with stock FFmpeg and optimized FFmpeg when
  both are available.

Note: FFmpeg `--enable-libnpp` is not enabled because current FFmpeg configure
rejects the installed CUDA/NPP 13 package layout on this host. CUDA scale/NVENC
paths are built and validated.

### 4. CUDA OpenCV Build

- [x] Clone/update OpenCV and `opencv_contrib`.
- [x] Provide Video Codec SDK header compatibility include directory from
  downloaded official SDK.
- [x] Configure OpenCV with `WITH_CUDA=ON`, `CUDA_ARCH_BIN=12.1`,
  `WITH_CUDNN=ON`, `OPENCV_DNN_CUDA=ON`, `WITH_NPP=ON`,
  `BUILD_opencv_cudacodec=ON`, FFmpeg, GStreamer, TBB, and Python 3 bindings.
- [x] Build and install into `/opt/gb10-cuda/install/opencv`.
- [x] Use isolated uv Python venv under `/opt/gb10-cuda/venvs/media`.
- [x] Validate `cv2.cuda.getCudaEnabledDeviceCount() > 0`.
- [x] Validate `cv2.getBuildInformation()` lists CUDA modules and cuDNN.
- [x] Run CPU vs CUDA resize/color benchmarks.

### 5. Python GPU Media Stack

- [x] Create `/opt/gb10-cuda/venvs/media`.
- [x] Install and validate `pynvvideocodec`, `cupy-cuda13x`, and compatible
  NVIDIA image/vision wheels when available for Linux SBSA.
- [x] Install and validate ML/audio packages that are compatible with Linux
  aarch64 and CUDA 13; document any x86-only or gated packages.
- [x] Validate PyNvVideoCodec imports in the Python 3.13 compatibility venv.
- [x] Validate CuPy CUDA access.
- [x] Evaluate CV-CUDA/nvImageCodec wheels; if unavailable or incompatible,
  document the exact blocker and build-from-source candidate.
- [x] Evaluate speech-to-text/text-to-speech routes: NVIDIA Riva/NIM
  containers where available for ARM/SBSA, and local TensorRT/Triton fallback
  where container images are unavailable.

Compatibility notes:

- Primary media venv `/opt/gb10-cuda/venvs/media` uses uv Python 3.14.5:
  OpenCV CUDA, CuPy CUDA 13, and `nvidia.nvimgcodec` validate here.
- PyNvVideoCodec currently imports on uv Python 3.13.13 in
  `/opt/gb10-cuda/venvs/media-cpython-3.13.13`. Its Python 3.14 wheel imports
  fail on `ast.Str` removal.
- Python 3.15.0b1 is installed as the uv default, but `cupy-cuda13x` does not
  yet publish `cp315` wheels, so CUDA Python workloads should use 3.14/3.13 for
  now.
- System Python has NVIDIA TensorRT 11.0.0.114 and ONNX 1.14.1 bindings from
  apt. The uv audio venv `/opt/gb10-cuda/venvs/audio-cpython-3.13.13` validates
  `nvidia-riva-client` 2.26.0. Sudo Docker with NVIDIA Container Toolkit sees
  the GB10 GPU; the user account is not currently allowed to access
  `/var/run/docker.sock`.

### 5A. Triton

- [x] Install Python Triton compiler package into the primary uv media venv.
- [x] Install CUDA-enabled PyTorch into the primary uv media venv so Triton's
  NVIDIA backend can detect and launch on CUDA.
- [x] Run a Triton Python compiler kernel smoke on GB10.
- [x] Pull the official NVIDIA Triton Inference Server Arm container
  `nvcr.io/nvidia/tritonserver:25.12-py3`.
- [x] Start Triton Inference Server with GPU access against an explicit empty
  model repository and validate `/v2/health/ready`.
- [x] Record Triton Server image digest and version.

Triton notes:

- Primary uv media venv has `torch 2.12.0+cu130` and `triton 3.7.0`.
- Triton compiler smoke validated a CUDA vector-add kernel on `NVIDIA GB10`.
- Triton Inference Server image digest:
  `nvcr.io/nvidia/tritonserver@sha256:895d0ad4c8a5cca1b089c757bd3449114444f31c711e48623fa1b4d94a43bc7d`.
- Triton Server smoke reported server version `2.64.0`, collected metrics for
  `NVIDIA GB10`, and exposed HTTP/gRPC/metrics endpoints on container ports
  `8000/8001/8002`.

### 6. Benchmarks

- [x] Generate synthetic H.264 test media when source media is not
  provided.
- [x] Benchmark baseline FFmpeg software decode/transcode.
- [x] Benchmark optimized FFmpeg NVDEC/NVENC/CUDA scale pipeline.
- [x] Benchmark OpenCV CPU operations.
- [x] Benchmark OpenCV CUDA operations.
- [x] Record `nvidia-smi dmon`/utilization during GPU benchmarks.
- [x] Save benchmark CSV/Markdown reports under `gb10-cuda/reports/`.

Latest benchmark evidence: `reports/benchmark-20260603T131127Z.md`,
`reports/benchmark-20260603T131127Z.csv`, and
`reports/benchmark-dmon-20260603T131127Z.log`.

### 7. Debug and Rollback

- [x] Provide `just debug-report` that captures enough state to diagnose failed
  builds without rerunning everything.
- [x] Provide `just clean-builds` for build-tree cleanup while preserving
  install prefixes and reports.
- [x] Provide `just purge-install` gated by an explicit environment variable.
- [x] Document rollback: remove `/opt/gb10-cuda`, deactivate venvs, and use
  distro `/usr/bin/ffmpeg` plus distro `python3-opencv`.

### 8. Final Acceptance

- [x] `just inventory`
- [x] `just install-deps`
- [x] `just build-ffmpeg`
- [x] `just validate-ffmpeg`
- [x] `just build-opencv`
- [x] `just validate-opencv`
- [x] `just install-triton-stack`
- [x] `just validate-triton-stack`
- [x] `just benchmark`
- [x] `just debug-report`
- [x] Update this TODO with completed status and benchmark summary.

Latest acceptance reports:

- Inventory: `reports/inventory-20260603T120628Z.md`
- FFmpeg validation: `reports/validate-ffmpeg-20260603T121328Z.md`
- uv Python setup: `reports/uv-python-20260603T122315Z.md`
- Official Video Codec SDK install: `reports/nvidia-gated-sdk-downloads-20260603T125100Z.md`
- Toolset validation: `reports/validate-toolsets-20260603T130705Z.md`
- OpenCV CUDA validation: `reports/validate-opencv-20260603T132542Z.md`
- Python GPU stack validation: `reports/validate-python-stack-20260603T132426Z.md`
- Triton install: `reports/install-triton-stack-20260603T132242Z.md`
- Triton validation: `reports/validate-triton-stack-20260603T132408Z.md`
- AI/audio validation: `reports/validate-ai-audio-stack-20260603T131216Z.md`
- Benchmark: `reports/benchmark-20260603T131127Z.md`
- Benchmark dmon: `reports/benchmark-dmon-20260603T131127Z.log`
- Debug capture: `reports/debug-20260603T132557Z.md`

### 9. Remaining Gap Work

The base GB10 CUDA media/AI stack is installed and validated, but the following
items remain open before treating the machine as fully tuned for production
media, CV, and AI/ML workloads.

#### 9.1 Runtime Compatibility Gaps

- [ ] Track and retest Python 3.15 CUDA wheel availability for `cupy-cuda13x`,
  `torch`, `triton`, `pynvvideocodec`, and `nvidia-nvimgcodec`. Current evidence:
  `reports/validate-python-stack-20260603T132426Z.md` shows `cp315` CUDA media
  wheels are not yet available.
- [ ] Track PyNvVideoCodec Python 3.14 compatibility. Current evidence:
  `reports/validate-python-stack-20260603T132426Z.md` shows the 3.14 import
  fails on `ast.Str`; Python 3.13 remains the validated compatibility venv.
- [ ] Decide whether to keep TensorRT Python bindings only on system Python or
  add a uv-compatible TensorRT Python route. Current state: apt validates
  `tensorrt 11.0.0.114` on `/usr/bin/python3`, not in the uv media venv.
- [ ] Add a lightweight dependency drift check that fails if uv package updates
  remove CUDA support from the media venv, especially for `torch`, `triton`,
  `cupy-cuda13x`, and `nvidia-*` CUDA wheels.

#### 9.2 FFmpeg and Video Codec Gaps

- [ ] Re-test FFmpeg `--enable-libnpp` against future CUDA/NPP and FFmpeg
  revisions. Current build validates CUDA scale and NVENC/NVDEC, but not
  FFmpeg's NPP filter path.
- [ ] Add a true NVDEC-only decode benchmark and an end-to-end decode -> GPU
  transform -> encode benchmark that avoids host transfers where possible.
- [ ] Add AV1 and HEVC benchmark cases in addition to the current H.264
  synthetic benchmark.
- [ ] Add a real media corpus benchmark using representative GoPro/POCUS/video
  inputs instead of only `lavfi` synthetic media.
- [ ] Add a Video Codec SDK sample build smoke from the official SDK archive,
  not just header installation and FFmpeg/OpenCV consumption.

#### 9.3 OpenCV and Computer Vision Gaps

- [ ] Add OpenCV `cudacodec` decode/encode functional tests with generated
  H.264/H.265 inputs.
- [ ] Add OpenCV CUDA benchmarks that keep frames resident on GPU across
  multiple operations; current microbenchmark includes transfer overhead and is
  not a final throughput model.
- [ ] Evaluate and, if viable on Linux SBSA, build CV-CUDA from source or add a
  documented blocker. Current stack validates `nvidia.nvimgcodec`, but not
  CV-CUDA.
- [ ] Add optical-flow validation beyond library presence. Current evidence
  confirms `libnvidia-opticalflow.so`; no separate Linux SBSA Optical Flow SDK
  archive was found in `~/Downloads`.

#### 9.4 Triton, TensorRT, and Model-Serving Gaps

- [ ] Add a real Triton model repository with at least one tiny ONNX or
  TensorRT engine and validate inference, not only server readiness.
- [ ] Add Triton HTTP/gRPC client smoke tests from the uv media or audio venv.
- [ ] Benchmark Triton model latency/throughput with GPU metrics and record
  pinned-memory and CUDA-memory-pool settings.
- [ ] Build or convert a tiny ONNX model with TensorRT and validate `trtexec`
  engine build/load on GB10.
- [ ] Evaluate whether Triton Server should run with explicit larger
  `--cuda-memory-pool-byte-size` / pinned-memory settings for DGX Spark unified
  memory behavior.

#### 9.5 Speech, NIM, and Container Gaps

- [ ] Pull and smoke-test the actual NGC Riva/NIM speech containers once the
  target image names and access policy are confirmed. Current validation only
  installs `nvidia-riva-client` and proves NVIDIA Docker GPU visibility.
- [ ] Use Bitwarden/NGC credentials for gated NGC pulls where required, without
  storing secrets in reports or scripts.
- [ ] Add STT/TTS client/server smoke scripts with synthetic audio fixtures.
- [ ] Decide whether Riva/NIM services should run under Docker Compose, systemd
  units, or a justfile-only operator workflow.
- [ ] Fix non-sudo Docker access if operator workflows should run containers as
  `damartel`; current validation requires `sudo docker`.

#### 9.6 Unified Memory and GB10-Specific Tuning Gaps

- [ ] Add CUDA managed-memory microbenchmarks that exercise oversubscription,
  prefetch, memory advice, and CPU/GPU shared-page behavior on GB10.
- [ ] Add TensorRT/Triton tests that vary workspace, pinned-memory, and CUDA
  memory pool sizes to identify useful defaults for the DGX Spark unified-memory
  architecture.
- [ ] Add Nsight Systems / Nsight Compute profiling recipes for the FFmpeg,
  OpenCV, Triton, and TensorRT benchmark paths.
- [ ] Use `ctadvisor` on at least one CUDA/OpenCV/Triton custom-kernel workload
  and record optimization recommendations.

#### 9.7 Automation and Quality Gaps

- [ ] Add machine-readable JSON summaries for inventory, validations, and
  benchmarks in addition to Markdown/CSV.
- [ ] Add a single `just acceptance` target that runs only the non-destructive
  validations and reports a compact pass/fail matrix.
- [ ] Add a `just benchmark-full` target that includes longer GPU-resident
  media, OpenCV, Triton, TensorRT, and memory benchmarks.
- [ ] Add cleanup policies for large Docker images, uv wheel caches, and build
  trees so `/opt/gb10-cuda` growth stays intentional.
- [ ] Add version pinning or lock artifacts for uv media/audio environments so
  reruns are reproducible across future wheel changes.
