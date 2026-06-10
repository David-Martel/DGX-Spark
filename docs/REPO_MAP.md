# Repository Map

## Root

- `README.md` - project overview, clone instructions, and public hygiene rules.
- `.gitmodules` - external repository links.
- `.gitignore` - local build, credential, generated-report, and model-artifact
  exclusions.

## Subprojects

- `gb10-cuda/` - DGX Spark / GB10 CUDA media and AI acceleration framework.
- `qsfp-cluster/` - NVIDIA Sync-backed QSFP/ConnectX-7 cluster automation,
  generated artifact handling, verification runbook, and optional user systemd
  timer units.
- `external/librealsense/` - submodule for David-Martel RealSense
  customizations.

## Generated Artifacts

Generated reports from `gb10-cuda` are local evidence by default. Keep them out
of Git unless they have been explicitly sanitized for public release.
