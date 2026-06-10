#!/usr/bin/env python3
"""Extract durable plan artifacts from NVIDIA Sync topology detection output."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


ROCE_DEVICE_BY_INTERFACE = {
    "enp1s0f0np0": "rocep1s0f0",
    "enp1s0f1np1": "rocep1s0f1",
    "enP2p1s0f0np0": "roceP2p1s0f0",
    "enP2p1s0f1np1": "roceP2p1s0f1",
}


def _load_envelope(path: Path) -> dict[str, Any]:
    last: dict[str, Any] | None = None
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        item = json.loads(line)
        if item.get("data"):
            last = item
    if not last:
        raise SystemExit(f"no data envelope found in {path}")
    error = last.get("error")
    if error:
        raise SystemExit(f"nvsync returned error: {error}")
    return last["data"]


def _host_index(nodes: dict[str, Any]) -> dict[str, int]:
    ordered = sorted(nodes, key=lambda alias: nodes[alias].get("hostname", alias))
    return {alias: idx + 1 for idx, alias in enumerate(ordered)}


def _cluster_alias(management_alias: str) -> str:
    if management_alias.startswith("nvsync-mgmt-"):
        return "nvsync-" + management_alias.removeprefix("nvsync-mgmt-")
    if management_alias.endswith("-mgmt"):
        return management_alias.removesuffix("-mgmt")
    return f"{management_alias}-cluster"


def _peer_ip_for(interface_ip: str, peer_nodes: dict[str, Any], interface: str) -> str | None:
    subnet_match = re.match(r"^(\d+\.\d+\.\d+)\.\d+/\d+$", interface_ip)
    if not subnet_match:
        return None
    subnet = subnet_match.group(1)
    for peer in peer_nodes.values():
        peer_ip = peer.get("interface_ips", {}).get(interface, "")
        if peer_ip.startswith(f"{subnet}."):
            return peer_ip.split("/", 1)[0]
    return None


def _rocev2_gid_index(alias_node: dict[str, Any], interface: str) -> int | None:
    ip = alias_node.get("interface_ips", {}).get(interface, "").split("/", 1)[0]
    if not ip:
        return None
    # Observed DGX Spark GID convention: first PCIe half exposes IPv4 RoCEv2 at
    # index 4, second half at index 3. Keep this mapping explicit so failed
    # tests are easy to diagnose if firmware changes it.
    if interface == "enp1s0f0np0" or interface == "enp1s0f1np1":
        return 4
    if interface == "enP2p1s0f0np0" or interface == "enP2p1s0f1np1":
        return 3
    return None


def write_artifacts(data: dict[str, Any], out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    nodes: dict[str, Any] = data["nodes"]

    (out_dir / "topology-summary.json").write_text(
        json.dumps(
            {
                "topology": data.get("topology"),
                "num_nodes": data.get("num_nodes"),
                "ip_scenario": data.get("ip_scenario"),
                "needs_apply": data.get("needs_apply"),
                "thresholds": data.get("thresholds", {}),
                "aliases": list(nodes),
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    with (out_dir / "netplan-paths.txt").open("w", encoding="utf-8") as fh:
        for alias, node in nodes.items():
            path = node.get("netplan_path")
            if path:
                fh.write(f"{alias}={path}\n")

    verify: dict[str, Any] = {}
    for alias, node in nodes.items():
        expected_ips = node.get("interface_ips", {})
        peer_nodes = {a: n for a, n in nodes.items() if a != alias}
        targets: list[str] = []
        for interface, address in expected_ips.items():
            peer_ip = _peer_ip_for(address, peer_nodes, interface)
            if peer_ip:
                targets.append(peer_ip)
        verify[alias] = {
            "expected_ips": expected_ips,
            "ping_targets": sorted(set(targets)),
        }
    (out_dir / "verify-config.json").write_text(
        json.dumps(verify, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    aliases = list(nodes)
    with (out_dir / "cluster-ssh-commands.txt").open("w", encoding="utf-8") as fh:
        for alias in aliases:
            peers = []
            for peer_alias in aliases:
                if peer_alias == alias:
                    continue
                peer_node = nodes[peer_alias]
                # Use the first interface IP as the stable cluster SSH target.
                first_ip = next(iter(peer_node.get("interface_ips", {}).values()), "")
                if first_ip:
                    peers.append(f"{_cluster_alias(peer_alias)}@{first_ip.split('/', 1)[0]}")
            if peers:
                fh.write(" ".join([alias, *peers]) + "\n")

    with (out_dir / "rdma-tests.tsv").open("w", encoding="utf-8") as fh:
        fh.write("local_alias\tremote_alias\troce_device\tgid_index\ttarget_ip\tport\n")
        if len(aliases) >= 2:
            local_alias = aliases[0]
            remote_alias = aliases[1]
            local_node = nodes[local_alias]
            remote_node = nodes[remote_alias]
            port = 18520
            for interface, address in sorted(local_node.get("interface_ips", {}).items()):
                device = ROCE_DEVICE_BY_INTERFACE.get(interface)
                gid_index = _rocev2_gid_index(local_node, interface)
                target_ip = remote_node.get("interface_ips", {}).get(interface, "").split("/", 1)[0]
                if device and gid_index is not None and target_ip:
                    fh.write(f"{local_alias}\t{remote_alias}\t{device}\t{gid_index}\t{target_ip}\t{port}\n")
                    port += 1

    with (out_dir / "interfaces-by-alias.txt").open("w", encoding="utf-8") as fh:
        for alias, node in nodes.items():
            interfaces = sorted(node.get("interface_ips", {}))
            fh.write(f"{alias}={','.join(interfaces)}\n")


def print_interfaces(data: dict[str, Any]) -> None:
    for alias, node in data["nodes"].items():
        interfaces = sorted(node.get("interface_ips", {}))
        print(f"{alias}={','.join(interfaces)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("detect_jsonl", type=Path)
    parser.add_argument("out_dir", type=Path)
    parser.add_argument("--print-interfaces", action="store_true")
    args = parser.parse_args()

    data = _load_envelope(args.detect_jsonl)
    if args.print_interfaces:
        print_interfaces(data)
    else:
        write_artifacts(data, args.out_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
