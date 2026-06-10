# DGX Spark QSFP/ConnectX-7 Cluster Automation

This folder contains a conservative automation wrapper for NVIDIA Sync Cluster
Assistant on DGX Spark / GB10 hosts. The wrapper keeps NVIDIA Sync as the
configuration engine and adds repeatable detection, backups, conflict cleanup,
verification artifacts, and focused RDMA checks.

## Current NVIDIA Guidance

As of the NVIDIA Sync and DGX Spark documentation current on 2026-06-10:

- DGX Spark has two rear QSFP/ConnectX-7 connectors.
- Each physical QSFP port exposes two Linux network interfaces and two RoCE
  devices because the 200 Gbps link is split over two PCIe 5.0 x4 links.
- A two-Spark direct pair should use one QSFP cable, connected to the same
  physical port on both devices.
- The ConnectX-7 network is separate from the management network. Keep Wi-Fi or
  10 GbE available for SSH, updates, NVIDIA Sync, and rollback.
- NVIDIA Sync Cluster Assistant is the preferred supported workflow. It writes
  `/etc/netplan/99-nvidia-sync-cluster.yaml` and node-to-node SSH aliases.
- NVIDIA Sync does not install a workload scheduler. NCCL, MPI, ROS 2, vLLM, or
  other workload launchers must be configured separately after the fabric is up.

References:

- NVIDIA Sync getting started:
  <https://docs.nvidia.com/sync/latest/getting-started.html>
- NVIDIA Sync Cluster Assistant:
  <https://docs.nvidia.com/sync/latest/cluster-assistant.html>
- NVIDIA Sync cluster network inspection:
  <https://docs.nvidia.com/sync/latest/cluster-network-inspection.html>
- DGX Spark stacking:
  <https://docs.nvidia.com/dgx/dgx-spark/spark-clustering.html>
- DGX Spark developer playbook, Connect Two Sparks:
  <https://build.nvidia.com/spark/connect-two-sparks/stacked-sparks>
- DGX Spark developer playbook, NCCL for Two Sparks:
  <https://build.nvidia.com/spark/nccl>

## Files

- `bin/spark_qsfp_cluster.sh` - operator entrypoint.
- `lib/extract_nvsync_plan.py` - converts NVIDIA Sync detection JSONL into
  durable plan artifacts.
- `artifacts/` - local generated output; ignored by Git.

## Recommended Alias Model

Use separate management aliases and cluster aliases.

Management aliases are stable LAN/mDNS aliases used by NVIDIA Sync to manage
nodes:

```sshconfig
Host nvsync-mgmt-3066
  HostName spark-3066.local
  User damartel
  IdentityFile ~/.ssh/id_ed25519_nvsync_spark
  IdentitiesOnly yes

Host nvsync-mgmt-0060
  HostName spark-0060.local
  User damartel
  IdentityFile ~/.ssh/id_ed25519_nvsync_spark
  IdentitiesOnly yes
```

Cluster aliases are created by NVIDIA Sync Cluster Assistant and point to
private ConnectX-7 addresses. Do not reuse management alias names for cluster
aliases.

## Safe Runbook

Inspect first:

```bash
cd ~/DGX-Spark
./qsfp-cluster/bin/spark_qsfp_cluster.sh doctor
./qsfp-cluster/bin/spark_qsfp_cluster.sh preflight
./qsfp-cluster/bin/spark_qsfp_cluster.sh detect
./qsfp-cluster/bin/spark_qsfp_cluster.sh snapshot-live
```

Apply the NVIDIA Sync configuration:

```bash
./qsfp-cluster/bin/spark_qsfp_cluster.sh configure \
  --apply \
  --clean-conflicts \
  --cluster-ssh
```

Verify after reboot or cable movement:

```bash
./qsfp-cluster/bin/spark_qsfp_cluster.sh verify
./qsfp-cluster/bin/spark_qsfp_cluster.sh rdma-test
```

Clean stale benchmark processes:

```bash
./qsfp-cluster/bin/spark_qsfp_cluster.sh cleanup-tests
```

## Conflict Handling

The common failure mode after reboots or manual experiments is that
NetworkManager autogenerates or restores a per-interface profile on a CX7
interface. NVIDIA Sync can write the correct Netplan file while live addresses
remain on an older profile.

Use `--clean-conflicts` only after `detect` identifies the intended CX7
interfaces. It deletes active NetworkManager profiles bound to those interfaces
before `set-network` runs. It does not delete Wi-Fi, RJ45, USB management, or
inactive saved profiles.

## Robustness Notes

- Always keep management access outside the QSFP fabric.
- Treat `/etc/netplan/99-nvidia-sync-cluster.yaml` as the Sync-managed source of
  truth.
- Snapshot `/etc/netplan` before applying changes. The wrapper does this during
  `configure`.
- If a non-DGX or non-GB10 node is present, NVIDIA Sync readiness checks should
  fail. Do not force unsupported nodes into Cluster Assistant.
- If cabling changes topology, delete the cluster in NVIDIA Sync, remove or
  replace the netplan file, then rerun detection.
- If a node was shut down or rebooted, run `verify` first. Re-run `configure`
  only when the expected netplan file or live addresses drift.
- If NVIDIA Sync discovery cannot build a fresh topology on an already
  configured fabric, run `snapshot-live` to regenerate verification and RDMA
  artifacts from current Sync-managed CX7 addresses.
- `snapshot-live` parses each node's `show_gids` output. Do not assume the same
  RoCEv2 GID index on both Sparks; firmware and interface ordering can differ.

## VIGIL Runtime Environment

For distributed VIGIL or model-runtime experiments, use the Sync-managed fabric:

```bash
export NCCL_SOCKET_IFNAME=enp1s0f0np0,enP2p1s0f0np0
export NCCL_IB_HCA=rocep1s0f0,roceP2p1s0f0
export NCCL_IB_DISABLE=0
export NCCL_NET_PLUGIN=none
export UCX_NET_DEVICES=enp1s0f0np0,enP2p1s0f0np0
```

Keep ROS 2 discovery and operator SSH on the management network unless a
specific experiment explicitly binds ROS traffic to the ConnectX-7 subnets.

## Automation Timeouts

Peer shutdowns, half-open SSH sessions, and mDNS stalls should produce bounded
failures, not hung operators or HIL jobs. The wrapper uses these defaults:

```bash
export SPARK_QSFP_NVSYNC_TIMEOUT=180
export SPARK_QSFP_NVSYNC_DOCTOR_TIMEOUT=15
export SPARK_QSFP_SSH_TIMEOUT=18
```

Increase the Sync timeout for first-time topology discovery on a slow management
network. Keep scheduled `doctor` and `verify` jobs short enough that a missing
peer is reported quickly.
