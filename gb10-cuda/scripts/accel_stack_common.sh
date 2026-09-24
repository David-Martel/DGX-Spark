#!/usr/bin/env bash
# Shared package policy for the DGX Spark / GB10 inference acceleration lane.

export GB10_INFERENCE_PYTHON="${GB10_INFERENCE_PYTHON:-cpython-3.13.13-linux-aarch64-gnu}"
export GB10_PROJECT_PYTHON="${GB10_PROJECT_PYTHON:-3.13.13}"
export GB10_TORCH_VERSION_SPEC="${GB10_TORCH_VERSION_SPEC:-2.12.*}"
export GB10_TORCHVISION_VERSION_SPEC="${GB10_TORCHVISION_VERSION_SPEC:-0.27.*}"
export GB10_TRITON_VERSION_SPEC="${GB10_TRITON_VERSION_SPEC:-3.7.*}"
# TensorRT is DERIVED from the system libnvinfer, not chosen -- see
# gb10_accel_tensorrt_packages(). Setting this env var overrides the
# derivation; leaving it unset is the supported path.
export GB10_TENSORRT_VERSION_SPEC="${GB10_TENSORRT_VERSION_SPEC:-}"
export GB10_TORCH_TENSORRT_TENSORRT_VERSION_SPEC="${GB10_TORCH_TENSORRT_TENSORRT_VERSION_SPEC:->=10.16,<10.17}"
export GB10_TORCH_TENSORRT_VERSION_SPEC="${GB10_TORCH_TENSORRT_VERSION_SPEC:-2.12.*}"
export GB10_ONNX_VERSION_SPEC="${GB10_ONNX_VERSION_SPEC:->=1.21,<2}"
export GB10_ONNXSCRIPT_VERSION_SPEC="${GB10_ONNXSCRIPT_VERSION_SPEC:->=0.7,<1}"
export GB10_CUDA_PYTHON_VERSION_SPEC="${GB10_CUDA_PYTHON_VERSION_SPEC:->=13.3,<13.4}"
# cuda-toolkit is TORCH-OWNED. torch 2.12 requires
#   cuda-toolkit[cudart,cufft,cufile,cupti,curand,cusolver,cusparse,
#                nvjitlink,nvrtc,nvtx]==13.0.2
# and resolves in the same uv invocation as torch, so a second hardcoded copy
# constrains nothing and silently goes stale (torch 2.13/2.14 want 13.0.3).
# Left empty on purpose; set it only to deliberately fight torch.
export GB10_CUDA_TOOLKIT_VERSION_SPEC="${GB10_CUDA_TOOLKIT_VERSION_SPEC:-}"
export GB10_FLASHINFER_VERSION_SPEC="${GB10_FLASHINFER_VERSION_SPEC:->=0.6.12,<0.7}"
export GB10_FLASH_ATTN_MAX_JOBS="${GB10_FLASH_ATTN_MAX_JOBS:-4}"
export GB10_FLASH_ATTN_NVCC_THREADS="${GB10_FLASH_ATTN_NVCC_THREADS:-1}"

gb10_accel_export_env() {
  export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
  export TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-12.1a}"
  export TRITON_PTXAS_PATH="${TRITON_PTXAS_PATH:-$CUDA_HOME/bin/ptxas}"
  export MAX_JOBS="${MAX_JOBS:-$GB10_FLASH_ATTN_MAX_JOBS}"
  export NVCC_THREADS="${NVCC_THREADS:-$GB10_FLASH_ATTN_NVCC_THREADS}"
}

gb10_accel_core_packages() {
  printf '%s\n' \
    numpy \
    packaging \
    psutil \
    ninja \
    dllist \
    "onnx$GB10_ONNX_VERSION_SPEC" \
    "onnxscript$GB10_ONNXSCRIPT_VERSION_SPEC" \
    "cuda-python$GB10_CUDA_PYTHON_VERSION_SPEC" \
    "cuda-toolkit[cudart]$GB10_CUDA_TOOLKIT_VERSION_SPEC" \
    "flashinfer-python$GB10_FLASHINFER_VERSION_SPEC" \
    "flashinfer-cubin$GB10_FLASHINFER_VERSION_SPEC" \
    "torch==$GB10_TORCH_VERSION_SPEC" \
    "torchvision==$GB10_TORCHVISION_VERSION_SPEC" \
    "triton==$GB10_TRITON_VERSION_SPEC"
}

# The version of the system TensorRT, i.e. the one `trtexec` is part of.
# `libnvinfer-bin` ships /usr/bin/trtexec; its version reads 11.2.1.2-1+cuda13.3
# and the part before the first '-' is the TensorRT version proper.
gb10_accel_system_tensorrt_version() {
  local version
  version="$(dpkg-query -W -f='${Version}' libnvinfer-bin 2>/dev/null)" || return 1
  version="${version%%-*}"
  [[ -n "$version" ]] || return 1
  printf '%s\n' "$version"
}

# TensorRT engine plans are version-locked. A plan built by the system trtexec
# cannot be deserialized by differently-versioned Python bindings -- IRuntime
# rejects it with "Error Code 6: ... expecting library version X got Y", and
# deserialize_cuda_engine() returns None rather than raising, so an unchecked
# caller proceeds with nothing. Measured on spark-0060 2026-09-10: system
# trtexec 11.2.1.2 built a plan that python tensorrt 11.0.0.114 refused.
#
# So the Python bindings are DERIVED from the deb, never chosen. The previous
# ">=11,<12" default was the defect in miniature: on 2026-09-10 it resolved to
# 11.3.0.99 against a system 11.2.1.2, i.e. provisioning a fresh host produced a
# brand-new skew. Fails closed -- no system TensorRT means there is nothing to
# match, and installing an arbitrary build is worse than not installing one.
gb10_accel_tensorrt_packages() {
  local spec="$GB10_TENSORRT_VERSION_SPEC" version
  if [[ -z "$spec" ]]; then
    if ! version="$(gb10_accel_system_tensorrt_version)"; then
      echo "gb10: cannot derive the TensorRT pin: package libnvinfer-bin is not installed." >&2
      echo "gb10: install the system TensorRT first, or set GB10_TENSORRT_VERSION_SPEC to override." >&2
      return 1
    fi
    spec="==$version"
  fi
  printf '%s\n' \
    "tensorrt-cu13$spec" \
    "tensorrt-lean-cu13$spec" \
    "tensorrt-dispatch-cu13$spec"
}

# `trtexec` embeds its own cudart (libnvinfer.so.11 carries zero libcudart
# strings), but it dlopens NVRTC from $CUDA_HOME -- measured on spark-0060:
#   /usr/local/cuda/targets/sbsa-linux/lib/libnvrtc.so.13
# and nvcc from the same tree is what compiles flash-attn under
# --no-build-isolation. That tree is therefore a real runtime dependency of this
# lane, and it is the only CUDA here that is neither torch's nor TensorRT's.
gb10_accel_require_system_cuda() {
  local minimum="${1:-13.2}" cuda_home="${CUDA_HOME:-/usr/local/cuda}" observed
  if [[ ! -x "$cuda_home/bin/nvcc" ]]; then
    echo "gb10: no nvcc at $cuda_home/bin/nvcc; a system CUDA >= $minimum is required." >&2
    return 1
  fi
  observed="$("$cuda_home/bin/nvcc" --version 2>/dev/null | sed -n 's/.*release \([0-9][0-9.]*\).*/\1/p')"
  if [[ -z "$observed" ]]; then
    echo "gb10: could not read a release version from $cuda_home/bin/nvcc --version." >&2
    return 1
  fi
  # Sort-based compare: the minimum must be the lower of the two.
  if [[ "$(printf '%s\n%s\n' "$minimum" "$observed" | sort -V | head -1)" != "$minimum" ]]; then
    echo "gb10: system CUDA $observed at $cuda_home is older than the required $minimum." >&2
    return 1
  fi
  printf 'gb10: system CUDA %s at %s (>= %s)\n' "$observed" "$(readlink -f "$cuda_home")" "$minimum"
}

gb10_accel_torch_tensorrt_package() {
  printf 'torch-tensorrt==%s\n' "$GB10_TORCH_TENSORRT_VERSION_SPEC"
}

gb10_accel_print_policy() {
  cat <<EOF
GB10 inference acceleration policy:
  Python: $GB10_INFERENCE_PYTHON
  Project Python: $GB10_PROJECT_PYTHON
  Torch: $GB10_TORCH_VERSION_SPEC
  TorchVision: $GB10_TORCHVISION_VERSION_SPEC
  Triton: $GB10_TRITON_VERSION_SPEC
  TensorRT CUDA 13: ${GB10_TENSORRT_VERSION_SPEC:-derived from system libnvinfer-bin}
  Torch-TensorRT: $GB10_TORCH_TENSORRT_VERSION_SPEC (--no-deps)
  ONNX: $GB10_ONNX_VERSION_SPEC
  ONNXScript: $GB10_ONNXSCRIPT_VERSION_SPEC
  CUDA Python: $GB10_CUDA_PYTHON_VERSION_SPEC
  CUDA Toolkit Python wheels: ${GB10_CUDA_TOOLKIT_VERSION_SPEC:-resolved by torch}
  FlashInfer: $GB10_FLASHINFER_VERSION_SPEC
  FlashAttention: latest best-effort, --no-build-isolation
  TORCH_CUDA_ARCH_LIST: ${TORCH_CUDA_ARCH_LIST:-12.1a}
EOF
}
