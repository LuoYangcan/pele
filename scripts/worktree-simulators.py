#!/usr/bin/env python3
"""Lease pooled simulators to checkouts; clean legacy linked-worktree registrations."""

import argparse
import contextlib
from datetime import datetime, timedelta, timezone
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys


LEASES = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "pele/simulator-leases.json"
LEASE_TTL = timedelta(hours=2)


class NoSimulator(Exception):
    pass


def command(args):
    return subprocess.check_output(args, text=True).strip()


def registered_worktrees(path):
    raw = command(["git", "-C", str(path), "worktree", "list", "--porcelain", "-z"])
    return [Path(item[9:]) for item in raw.split("\0") if item.startswith("worktree ")]


def registrations(root, suffix=None):
    files = sorted(p for p in (root / ".claude").glob("sim-udid*")
                   if p.name == "sim-udid" or p.name.startswith("sim-udid-"))
    if suffix:
        files = [p for p in files if p.name == "sim-udid-" + suffix]
    result = {}
    for path in files:
        if path.is_file():
            value = path.read_text().strip()
            if not re.fullmatch(r"[0-9a-fA-F-]{36}", value):
                raise ValueError(f"invalid simulator registration: {path}")
            result[path] = value.upper()
    return result


def devices():
    data = json.loads(command(["xcrun", "simctl", "list", "devices", "-j"]))
    return {d["udid"].upper(): dict(d, runtime=runtime)
            for runtime, rows in data["devices"].items() for d in rows}


def runtime_suffix(runtime):
    # iOS-18-6 → ios18-6, matching legacy .claude/sim-udid-<suffix> names.
    return re.sub(r"^([a-z]+)-", r"\1", runtime.split("SimRuntime.")[-1].lower())


def read_leases():
    return json.loads(LEASES.read_text()) if LEASES.exists() else {}


@contextlib.contextmanager
def lease_store():
    """Yield the machine-wide lease map under an exclusive lock and persist it on exit."""
    LEASES.parent.mkdir(parents=True, exist_ok=True)
    with LEASES.with_suffix(".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        leases = read_leases()
        yield leases
        temp = LEASES.with_suffix(".tmp")
        temp.write_text(json.dumps(leases, indent=2, sort_keys=True) + "\n")
        os.replace(temp, LEASES)


def pool_eligible(device, runtime):
    # Generated sim-<slug> devices belong to legacy worktree registrations.
    return (device.get("isAvailable") and ".SimRuntime.iOS-" in device["runtime"]
            and ".SimDeviceType.iPhone" in device.get("deviceTypeIdentifier", "")
            and not device["name"].startswith("sim-")
            and (not runtime or device["runtime"].endswith(".SimRuntime." + runtime)))


def ensure(owner, runtime):
    slot = runtime or "default"
    now = datetime.now(timezone.utc)
    all_devices = devices()
    with lease_store() as leases:
        for udid, lease in list(leases.items()):
            if (udid not in all_devices or not Path(lease["owner"]).exists()
                    or now - datetime.fromisoformat(lease["renewed_at"]) >= LEASE_TTL):
                del leases[udid]
        held = {u for u, lease in leases.items() if lease["owner"] == str(owner) and lease["slot"] == slot}
        free = [(u, d) for u, d in all_devices.items()
                if pool_eligible(d, runtime) and (u not in leases or u in held)]
        if not free:
            busy = [f"{all_devices[u]['name']} ({u}) leased by {lease['owner']} at {lease['renewed_at']}"
                    for u, lease in leases.items() if pool_eligible(all_devices[u], runtime)]
            wanted = "iPhone simulator" + (f" on {runtime}" if runtime else "")
            raise NoSimulator(f"no free {wanted}" + "".join("\n  " + row for row in busy))
        udid, device = max(free, key=lambda row: (row[0] in held, row[1].get("lastUsedAt", "")))
        for stale in held - {udid}:
            del leases[stale]
        leases[udid] = {"owner": str(owner), "slot": slot, "renewed_at": now.isoformat(timespec="seconds")}
    boot = subprocess.run(["xcrun", "simctl", "boot", udid], capture_output=True, text=True)
    if boot.returncode and "Booted" not in boot.stderr:
        print("WARN: simctl boot: " + boot.stderr.strip(), file=sys.stderr)
    print(f"SIMULATOR_UDID={udid}\nSIM_NAME={device['name']}")


def owned(lease, targets, suffix=None):
    return (lease is not None and Path(lease["owner"]) in targets
            and (not suffix or lease["slot"] != "default" and runtime_suffix(lease["slot"]) == suffix))


def release(targets, suffix=None):
    with lease_store() as leases:
        mine = [u for u, lease in leases.items() if owned(lease, targets, suffix)]
        for udid in mine:
            del leases[udid]
    return mine


def inspect(roots, targets, all_devices, suffix=None):
    leases = read_leases()
    owners = {}
    for root in roots:
        if root.exists():
            for path, udid in registrations(root).items():
                owners.setdefault(udid, []).append((root, path))
    selected = {}
    for root in targets:
        for path, udid in registrations(root, suffix).items():
            selected.setdefault(udid, []).append(path)
    rows = []
    for udid in sorted(set(all_devices) | set(selected) | set(leases)):
        device = all_devices.get(udid)
        lease = leases.get(udid)
        name_matches = []
        if device:
            for root in roots:
                base = "sim-" + root.name
                expected = {base + "-" + suffix} if suffix else {base, base + "-" + runtime_suffix(device["runtime"])}
                if device["name"] in expected:
                    name_matches.append(root)
        if (udid not in selected and not owned(lease, targets, suffix)
                and not any(p in targets for p in name_matches)):
            continue
        references = owners.get(udid, [])
        outside = [str(root) for root, _ in references if root not in targets]
        if lease and Path(lease["owner"]) not in targets:
            outside.append(lease["owner"] + " (lease)")
        if outside:
            status = "shared"
        elif lease:
            # Pooled devices keep their login state; cleanup only releases the lease.
            status = "leased"
        elif udid in selected:
            status = "registered" if device else "stale-registration"
        elif len(name_matches) == 1 and not references:
            status = "name-candidate"
        else:
            status = "ambiguous"
        rows.append({"udid": udid, "name": device["name"] if device else None,
                     "state": device["state"] if device else "absent", "status": status,
                     "registration_files": [str(p) for p in selected.get(udid, [])],
                     "other_owners": outside, "name_matches": [str(p) for p in name_matches],
                     "lease": lease})
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["ensure", "inspect", "release", "shutdown", "delete"])
    parser.add_argument("--worktree", type=Path, action="append", required=True)
    parser.add_argument("--runtime", help="ensure: lease a separate device on this runtime (e.g. iOS-18-6)")
    parser.add_argument("--suffix", help="Restrict to one runtime registration suffix")
    parser.add_argument("--include-named", action="store_true",
                        help="Also act on unambiguous generated-name candidates after inspection")
    args = parser.parse_args()
    targets = [p.resolve() for p in args.worktree]
    if args.action == "ensure":
        if len(targets) != 1:
            raise ValueError("ensure takes exactly one --worktree checkout")
        ensure(targets[0], args.runtime)
        return 0
    roots = []
    for target in targets:
        repo_roots = registered_worktrees(target)
        if target not in repo_roots[1:] or not (target / ".git").is_file():
            raise ValueError(f"not a registered linked worktree: {target}")
        roots.extend(p for p in repo_roots if p not in roots)
    if args.action == "release":
        for udid in release(targets, args.suffix):
            print(f"released lease: {udid}")
        return 0
    rows = inspect(roots, targets, devices(), args.suffix)
    if args.action == "inspect":
        print(json.dumps(rows, ensure_ascii=False, indent=2))
        return 0
    failed = False
    for row in rows:
        status = row["status"]
        if status == "leased":
            continue
        if status not in {"registered", "stale-registration"} and not (
                status == "name-candidate" and args.include_named):
            print(f"retained {row['udid']}: {status}", file=sys.stderr)
            failed = True
            continue
        # Refresh immediately before mutation; another worktree may now reference it.
        fresh_roots = []
        for target in targets:
            fresh_roots.extend(p for p in registered_worktrees(target) if p not in fresh_roots)
        fresh = inspect(fresh_roots, targets, devices(), args.suffix)
        current = next((r for r in fresh if r["udid"] == row["udid"]), None)
        if not current or current["status"] != status:
            print(f"association changed; retained {row['udid']}", file=sys.stderr)
            failed = True
            continue
        udid = row["udid"]
        if current["state"] != "absent":
            if current["state"] != "Shutdown":
                subprocess.run(["xcrun", "simctl", "shutdown", udid], check=True)
            if args.action == "delete":
                subprocess.run(["xcrun", "simctl", "delete", udid], check=True)
        remaining = devices().get(udid)
        if args.action == "delete":
            if remaining:
                raise RuntimeError(f"delete not verified: {udid}")
            for filename in row["registration_files"]:
                path = Path(filename)
                if path.exists() and path.read_text().strip().upper() == udid:
                    path.unlink()
        elif remaining and remaining["state"] != "Shutdown":
            raise RuntimeError(f"shutdown not verified: {udid}")
        print(f"{args.action}: {udid} ({row['name'] or 'already absent'})")
    # Release after legacy cleanup so a leased device never falls back to "registered" and gets deleted.
    names = {row["udid"]: row["name"] for row in rows}
    for udid in release(targets, args.suffix):
        print(f"released lease: {udid} ({names.get(udid) or 'device absent'})")
    if not rows:
        print("no lease, registered or generated-name simulator association found")
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except NoSimulator as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(3)
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
