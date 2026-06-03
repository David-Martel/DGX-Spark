# GB10 CUDA Publication Notes

The framework copied into this repository is the reusable automation surface
from the local DGX Spark host. The local reports and logs are intentionally not
published because they can include hostnames, usernames, UUIDs, package
inventory, paths, and other machine-specific evidence.

## Published

- Build and validation scripts.
- `justfile` command surface.
- Operator README.
- TODO/checklist with completed evidence references and remaining gap work.

## Not Published

- `gb10-cuda/reports/*.md`, `*.csv`, and `*.log`.
- `/opt/gb10-cuda` sources, builds, installs, venvs, logs, state markers, and
  SDK extracts.
- Bitwarden sessions, NGC credentials, cookies, or gated SDK archives.

## Submodule

`external/librealsense` is a Git submodule. To update it:

```bash
git submodule update --remote external/librealsense
git status --short
```

Commit the submodule pointer change in this repository only when the referenced
`librealsense` revision is the intended integration point.
