#!/usr/bin/env python3
"""Build QSFP verification artifacts from live DGX Spark interface state."""

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


def _cluster_alias(management_alias: str) -> str:
    if management_alias.startswith("nvsync-mgmt-"):
        return "nvsync-" + management_alias.removeprefix("nvsync-mgmt-")
    if management_alias.endswith("-mgmt"):
        return management_alias.removesuffix("-mgmt")
    return f"{management_alias}-cluster"


def _ipv4_cidr(interface: dict[str, Any], ip_base: str) -> str | None:
    for address in interface.get("addr_info", []):
        if address.get("family") != "inet":
            continue
        local = str(address.get("local", ""))
        prefixlen = address.get("prefixlen")
        if local.startswith(f"{ip_base}.") and prefixlen:
            return f"{local}/{prefixlen}"
    return None


def _load_node(run_dir: Path, alias: str, ip_base: str) -> dict[str, Any]:
    path = run_dir / f"live-ip-{alias}.json"
    interfaces = json.loads(path.read_text(encoding="utf-8"))
    interface_ips: dict[str, str] = {}
    for interface in interfaces:
        name = str(interface.get("ifname", ""))
        if name not in ROCE_DEVICE_BY_INTERFACE:
            continue
        cidr = _ipv4_cidr(interface, ip_base)
        if cidr:
            interface_ips[name] = cidr
    if not interface_ips:
        raise SystemExit(f"{alias}: no {ip_base}.x IPv4 addresses found on known CX7 interfaces")
    return {
        "interface_ips": dict(sorted(interface_ips.items())),
        "netplan_path": "/etc/netplan/99-nvidia-sync-cluster.yaml",
    }


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


def _rocev2_gid_index(interface: str) -> int | None:
    if interface in {"enp1s0f0np0", "enp1s0f1np1"}:
        return 4
    if interface in {"enP2p1s0f0np0", "enP2p1s0f1np1"}:
        return 3
    return None


def _load_rocev2_gid_indexes(run_dir: Path, alias: str) -> dict[tuple[str, str], int]:
    path = run_dir / f"live-show-gids-{alias}.txt"
    if not path.exists():
        return {}
    indexes: dict[tuple[str, str], int] = {}
    pattern = re.compile(
        r"^(?P<device>\S+)\s+\d+\s+(?P<index>\d+)\s+\S+\s+"
        r"(?P<ipv4>\d+\.\d+\.\d+\.\d+)\s+v2\s+(?P<netdev>\S+)"
    )
    for line in path.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line.strip())
        if not match:
            continue
        indexes[(match.group("device"), match.group("ipv4"))] = int(match.group("index"))
    return indexes


def _write_artifacts(run_dir: Path, aliases: list[str], nodes: dict[str, Any]) -> None:
    (run_dir / "topology-summary.json").write_text(
        json.dumps(
            {
                "topology": "live_snapshot",
                "num_nodes": len(nodes),
                "ip_scenario": "existing_sync_managed",
                "needs_apply": False,
                "aliases": aliases,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    with (run_dir / "netplan-paths.txt").open("w", encoding="utf-8") as fh:
        for alias, node in nodes.items():
            fh.write(f"{alias}={node['netplan_path']}\n")

    verify: dict[str, Any] = {}
    for alias, node in nodes.items():
        peer_nodes = {a: n for a, n in nodes.items() if a != alias}
        targets: list[str] = []
        for interface, address in node["interface_ips"].items():
            peer_ip = _peer_ip_for(address, peer_nodes, interface)
            if peer_ip:
                targets.append(peer_ip)
        verify[alias] = {
            "expected_ips": node["interface_ips"],
            "ping_targets": sorted(set(targets)),
        }
    (run_dir / "verify-config.json").write_text(
        json.dumps(verify, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    with (run_dir / "cluster-ssh-commands.txt").open("w", encoding="utf-8") as fh:
        for alias in aliases:
            peers = []
            for peer_alias in aliases:
                if peer_alias == alias:
                    continue
                first_ip = next(iter(nodes[peer_alias]["interface_ips"].values()), "")
                if first_ip:
                    peers.append(f"{_cluster_alias(peer_alias)}@{first_ip.split('/', 1)[0]}")
            if peers:
                fh.write(" ".join([alias, *peers]) + "\n")

    gid_indexes = {alias: _load_rocev2_gid_indexes(run_dir, alias) for alias in aliases}
    with (run_dir / "rdma-tests.tsv").open("w", encoding="utf-8") as fh:
        fh.write(
            "local_alias\tremote_alias\troce_device\tlocal_gid_index\t"
            "remote_gid_index\ttarget_ip\tport\n"
        )
        if len(aliases) >= 2:
            local_alias = aliases[0]
            remote_alias = aliases[1]
            port = 18520
            for interface in sorted(nodes[local_alias]["interface_ips"]):
                device = ROCE_DEVICE_BY_INTERFACE.get(interface)
                local_ip = nodes[local_alias]["interface_ips"][interface].split("/", 1)[0]
                target_ip = nodes[remote_alias]["interface_ips"].get(interface, "").split("/", 1)[0]
                fallback_gid_index = _rocev2_gid_index(interface)
                local_gid_index = gid_indexes[local_alias].get(
                    (device, local_ip),
                    fallback_gid_index,
                )
                remote_gid_index = gid_indexes[remote_alias].get(
                    (device, target_ip),
                    fallback_gid_index,
                )
                if (
                    device
                    and local_gid_index is not None
                    and remote_gid_index is not None
                    and target_ip
                ):
                    fh.write(
                        f"{local_alias}\t{remote_alias}\t{device}\t{local_gid_index}\t"
                        f"{remote_gid_index}\t{target_ip}\t{port}\n"
                    )
                    port += 1

    with (run_dir / "interfaces-by-alias.txt").open("w", encoding="utf-8") as fh:
        for alias, node in nodes.items():
            interfaces = sorted(node["interface_ips"])
            fh.write(f"{alias}={','.join(interfaces)}\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("run_dir", type=Path)
    parser.add_argument("aliases", nargs="+")
    parser.add_argument("--ip-base", default="10.55")
    args = parser.parse_args()

    nodes = {alias: _load_node(args.run_dir, alias, args.ip_base) for alias in args.aliases}
    _write_artifacts(args.run_dir, args.aliases, nodes)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
