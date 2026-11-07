"""Formatting helpers for gcp-ops.sh (TBX-307).

Everything that needs more than a one-liner of parsing lives here rather than in
inline ``python3 -c`` strings: the wrapper pipes gcloud JSON in and gets tables
out. Pure stdlib, no side effects beyond stdout — ``projects`` is the one command
that calls gcloud itself (per-project billing lookups).
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from collections import Counter

# Asset types every project carries that say nothing about cost or activity.
NOISE_TYPES = {
    "serviceusage.googleapis.com/Service",
    "logging.googleapis.com/LogBucket",
    "logging.googleapis.com/LogSink",
    "compute.googleapis.com/Network",
    "compute.googleapis.com/Subnetwork",
    "compute.googleapis.com/Firewall",
    "compute.googleapis.com/Route",
    "compute.googleapis.com/Project",
    "compute.googleapis.com/InstanceSettings",
    "iam.googleapis.com/ServiceAccount",
    "iam.googleapis.com/ServiceAccountKey",
    "cloudresourcemanager.googleapis.com/Project",
    "cloudbilling.googleapis.com/ProjectBillingInfo",
    "monitoring.googleapis.com/AlertPolicy",
}


def _read_json_stream(fh) -> list:
    """Concatenated JSON arrays (one per gcloud call) -> one flat list."""
    rows: list = []
    decoder = json.JSONDecoder()
    text = fh.read()
    pos = 0
    while True:
        while pos < len(text) and text[pos].isspace():
            pos += 1
        if pos >= len(text):
            break
        obj, pos = decoder.raw_decode(text, pos)
        rows.extend(obj if isinstance(obj, list) else [obj])
    return rows


def _project_of(asset: dict) -> str:
    return (asset.get("project") or asset.get("parentFullResourceName") or "").split("/")[-1]


def cmd_projects(config: str, unreachable: str, closed_bas: str) -> None:
    rows = _read_json_stream(sys.stdin)
    env = {**os.environ, "CLOUDSDK_ACTIVE_CONFIG_NAME": config}
    out = []
    seen: set[str] = set()
    for p in rows:
        pid = p["projectId"]
        if pid in seen:
            continue
        seen.add(pid)
        r = subprocess.run(
            [
                "gcloud",
                "billing",
                "projects",
                "describe",
                pid,
                "--format=value(billingAccountName,billingEnabled)",
            ],
            capture_output=True,
            text=True,
            env=env,
            check=False,
        )
        if r.returncode == 0:
            name, _, enabled = r.stdout.strip().partition("\t")
            ba = name.replace("billingAccounts/", "") or "(none)"
            ba = f"{ba} ({'on' if enabled == 'True' else 'off'})"
        else:
            ba = "? (no billing.projects.get)"
        parent = p.get("parent", {})
        out.append(
            (
                pid,
                p.get("name", ""),
                p.get("projectNumber", ""),
                p.get("lifecycleState", ""),
                f"{parent.get('type', '-')}/{parent.get('id', '-')}",
                ba,
                p.get("createTime", "")[:10],
            )
        )
    out.sort()
    print(
        f"{'PROJECT_ID':<32} {'NAME':<34} {'NUMBER':<14} {'STATE':<8} {'PARENT':<28} "
        f"{'BILLING_ACCOUNT (enabled)':<32} CREATED"
    )
    for r in out:
        print(f"{r[0]:<32} {r[1][:33]:<34} {r[2]:<14} {r[3]:<8} {r[4]:<28} {r[5]:<32} {r[6]}")
    print(f"\n{len(out)} projects reachable")
    if unreachable.strip():
        print(
            f"Known but UNREACHABLE (no rights; from accounts/<alias>.conf): {unreachable.strip()}"
        )
    if closed_bas.strip():
        print(f"Closed / unreachable billing accounts: {closed_bas.strip()}")


def _project_ids(projects_file: str) -> dict[str, str]:
    """projectNumber -> projectId, from a `gcloud projects list --format=json` dump."""
    if not projects_file or not os.path.exists(projects_file):
        return {}
    with open(projects_file, encoding="utf-8") as fh:
        try:
            return {p["projectNumber"]: p["projectId"] for p in _read_json_stream(fh)}
        except (KeyError, ValueError):
            return {}


def cmd_inventory(include_all: bool, as_json: bool, project: str, projects_file: str = "") -> None:
    rows = _read_json_stream(sys.stdin)
    ids = _project_ids(projects_file)
    for r in rows:  # the search API names projects by number; readers think in ids
        r["projectId"] = ids.get(_project_of(r), _project_of(r))
    if not include_all:
        rows = [r for r in rows if r.get("assetType") not in NOISE_TYPES]
    if as_json:
        print(json.dumps(rows, indent=1))
        return
    noise_note = "noise types included" if include_all else "noise types hidden — add --all"
    if project:
        rows.sort(key=lambda r: (r.get("assetType", ""), r.get("name", "")))
        header = f"{'ASSET_TYPE':<52} {'LOCATION':<16} {'STATE':<12} {'CREATED':<11} "
        print(header + f"{'UPDATED':<11} NAME")
        for r in rows:
            name = r.get("name", "")
            short = name.split("/", 3)[-1] if name else ""
            print(
                f"{r.get('assetType', '')[:51]:<52} {r.get('location', '')[:15]:<16} "
                f"{r.get('state', '')[:11]:<12} {r.get('createTime', '')[:10]:<11} "
                f"{r.get('updateTime', '')[:10]:<11} {short}"
            )
        print(f"\n{len(rows)} resources ({noise_note})")
        return
    counts = Counter((r["projectId"], r.get("assetType", "")) for r in rows)
    last: dict[str, str] = {}
    for r in rows:
        p = r["projectId"]
        t = r.get("updateTime") or r.get("createTime") or ""
        if t > last.get(p, ""):
            last[p] = t
    print(f"{'PROJECT':<34} {'ASSET_TYPE':<52} COUNT")
    for (p, t), n in sorted(counts.items()):
        print(f"{p:<34} {t[:51]:<52} {n}")
    print(f"\n{'PROJECT':<34} LAST_RESOURCE_CHANGE   (max updateTime over the listed assets)")
    for p, t in sorted(last.items()):
        print(f"{p:<34} {t[:19]}")
    print(f"\n{len(rows)} resources in {len(last)} projects ({noise_note})")


def main(argv: list[str]) -> None:
    if not argv:
        sys.exit("gcp_ops_lib: command required (projects | inventory)")
    cmd, args = argv[0], argv[1:]
    if cmd == "projects":
        cmd_projects(*args)
    elif cmd == "inventory":
        cmd_inventory(args[0] == "1", args[1] == "1", args[2], args[3] if len(args) > 3 else "")
    else:
        sys.exit(f"gcp_ops_lib: unknown command {cmd}")


if __name__ == "__main__":
    main(sys.argv[1:])
