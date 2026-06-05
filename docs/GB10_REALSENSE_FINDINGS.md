# GB10 RealSense acceleration — platform findings

Reusable DGX Spark / GB10 (aarch64, CUDA 13) findings from hardening and GPU-accelerating the Intel
RealSense (D400) capture→process→render pipeline in `external/librealsense`. Full HIL-measured detail
lives in the submodule: [`external/librealsense/docs/gb10/`](../external/librealsense/docs/gb10/README.md).

## Headline results (all HIL-measured on a GB10 host)
- **CUDA acceleration is op-dependent on GB10 — not a blanket win:**
  - `rs.align` (depth→color): **CUDA 15–19× faster than hand-written NEON**. Already uses cached device
    buffers, which is *why* it is fast.
  - `rs.pointcloud`: as shipped, CUDA was **0.57× (slower)** — the cost was **per-frame `cudaMalloc`/`cudaFree`
    churn, not the host↔device copy**. Caching the device buffers makes it **3.3× faster than the shipped path
    and faster than NEON**. `cudaMallocManaged` (unified-memory) was *not* faster than cached device buffers.
  - Color format conversion (YUYV→RGB): CUDA is **CPU-neutral vs NEON** end-to-end (DMA/plumbing-bound);
    caching its buffers trims ~25–30% of the stage's CPU to NEON-parity.
  - `rs.colorizer`: **no CUDA path** (its only GPU path is OpenGL).
- **Shared-memory lesson:** on GB10's coherent memory the lever is **eliminating per-frame allocation churn
  (cache device buffers), not eliminating copies** — a `cudaMemcpy` over the shared RAM is cheap.
- **OpenGL processing blocks** (`gl::colorizer/pointcloud/align`) run on the GPU (`GL_RENDERER = NVIDIA
  GB10/PCIe`) but are **C++-only (no Python binding)**; `gl::colorizer` is correct yet ~2.3× slower than NEON
  for a CPU consumer, and `gl::pointcloud/align` return GPU-side frames (no CPU readback) — GL is only worth it
  as a keep-on-GPU chain.
- **NVENC** (h264/hevc/av1, NVENC v13) is the GPU-to-disk video path; raw `rosbag2 .db3` is uncompressed/CPU.
- **TensorRT**: the geometric capture/align/pointcloud pipeline has no neural stage to accelerate; a `trtexec`
  capability probe shows a small learned depth-filter has large headroom (≈37× at 30 fps) for a *future*
  learned-filter stage.
- **USB-controller stability:** sustained multi-stream load can trip a GB10 xHCI Stop-Endpoint defect (NVIDIA
  silicon/BSP). Opt-in mitigations (deeper URB pool, gentler stop, re-acquire guard) reduce the trigger
  surface; single-stream is the conservative-safe envelope.

## End-to-end demonstrator
A RealSense **RGB+D → real-time 2D keypoint inference → 3D depth-lift → headless EGL OpenGL render → NVENC**
pipeline runs **live on GB10 at ~30 fps, controller-safe**, with per-stage CUDA-event telemetry. See the
test-bed plan in the submodule docs.

## Opt-in build flags (all OFF by default = upstream-identical)
Built via `external/librealsense/scripts/build-dgx-spark-gb10.sh`:
`LRS_GB10_USB_TUNING` (xHCI mitigations), `LRS_GB10_PC_ZEROCOPY` (+ runtime `RS2_PC_MODE=1`),
`LRS_GB10_CONV_CACHE` (+ runtime `RS2_CONV_MODE=1`). The cached ladders are byte-identical to baseline and
runtime-gated off by default.
