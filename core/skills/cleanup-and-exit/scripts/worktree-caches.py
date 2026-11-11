#!/usr/bin/env python3
"""Inspect or remove allowlisted generated caches in registered linked worktrees."""

import argparse
from collections import Counter
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess


DERIVED_CHILDREN = (
    "Build/Intermediates.noindex", "Build/Products", "ModuleCache.noindex",
    "SDKExplicitPrecompiledModules", "SDKStatCaches.noindex", "Index.noindex",
    "CompilationCache.noindex", "SymbolCache.noindex",
)
BUILD_TOOLS = {
    "xcodebuild", "xcbuild", "xcbuildservice", "xcbbuildservice", "swift-build", "swift-test",
    "swift-frontend", "swiftc", "clang", "clang++", "cc", "c++", "gcc",
    "g++", "make", "ninja", "xctest",
}
PROTECTED_NAMES = {".git", "SourcePackages", "checkouts", "repositories", "artifacts", "Logs"}
PROTECTED_SUFFIXES = (".xcresult", ".xcarchive", ".log", ".xcactivitylog")
STATUSES = ("removed", "already_absent", "retained", "failed", "recreated")


def run(args, cwd=None):
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True, check=False)


def git(worktree, *args):
    result = run(["git", "-C", str(worktree), *args])
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or f"git {' '.join(args)} failed ({result.returncode})")
    return result.stdout


def inside(path, root):
    return path == root or root in path.parents


def unchanged_path(path):
    return path.is_absolute() and path.resolve() == path and not any(
        part.is_symlink() for part in (path, *path.parents)
    )


def verify_worktree(worktree):
    if not unchanged_path(worktree):
        raise ValueError("worktree or an ancestor is a symlink or resolves to a different path")
    root = Path(git(worktree, "rev-parse", "--show-toplevel").strip())
    if root != worktree:
        raise ValueError(f"not the exact Git worktree root: {root}")
    registered = [Path(field[9:]) for field in git(worktree, "worktree", "list", "--porcelain", "-z").split("\0")
                  if field.startswith("worktree ")]
    if not registered or worktree not in registered:
        raise ValueError("exact worktree path is not registered")
    if worktree == registered[0]:
        raise ValueError("primary worktree is excluded")


def candidate_paths(worktree):
    candidates = [(worktree / root / child, None)
                  for root in ("build/DerivedData", "DerivedData") for child in DERIVED_CHILDREN]
    retained = []
    manifests = git(worktree, "ls-files", "-z").split("\0")
    packages = sorted({(worktree / name).parent for name in manifests
                       if name and Path(name).name == "Package.swift"})
    triple = re.compile(r"[A-Za-z0-9_]+(?:-[A-Za-z0-9_.]+){2,}\Z")
    for package in packages:
        build = package / ".build"
        if os.path.lexists(build) and (not unchanged_path(build) or not build.is_dir()):
            retained.append({"path": str(build), "status": "retained", "size_bytes": None,
                             "reason": "package build root is not a local directory without symlinks"})
            continue
        for parent in (build, build / "index-build"):
            if not os.path.lexists(parent):
                continue
            if not unchanged_path(parent) or not parent.is_dir():
                retained.append({"path": str(parent), "status": "retained", "size_bytes": None,
                                 "reason": "package index build root is not a local directory without symlinks"})
                continue
            for architecture in sorted(parent.iterdir()):
                if triple.fullmatch(architecture.name):
                    for configuration in ("debug", "release"):
                        for child in ("ModuleCache", "index"):
                            candidates.append((architecture / configuration / child, package))
    return candidates, retained


def inspect_candidate(worktree, path):
    entry = {"path": str(path), "status": "retained", "size_bytes": None, "apparent_bytes": None}
    if not unchanged_path(path):
        return entry | {"reason": "cache or an ancestor is a symlink or resolves to a different path"}
    if not os.path.lexists(path):
        return entry | {"status": "already_absent", "reason": "exact cache path is absent", "size_bytes": 0, "apparent_bytes": 0}
    if not path.is_dir():
        return entry | {"reason": "allowlisted cache path is not a directory"}
    relative = str(path.relative_to(worktree))
    if git(worktree, "ls-files", "-z", "--", relative):
        return entry | {"reason": "cache contains Git-tracked content"}
    ignored = run(["git", "-C", str(worktree), "check-ignore", "-q", "--", relative])
    if ignored.returncode == 1:
        return entry | {"reason": "cache path is not Git-ignored"}
    if ignored.returncode:
        raise RuntimeError(ignored.stderr.strip() or "git check-ignore failed")
    size = apparent = 0
    protected = []

    def walk_error(error):
        raise error

    for directory, directories, files in os.walk(path, followlinks=False, onerror=walk_error):
        for name in [*directories, *files]:
            child = Path(directory) / name
            stat = child.lstat()
            size += stat.st_blocks * 512
            apparent += stat.st_size
            if name in PROTECTED_NAMES or name.endswith(PROTECTED_SUFFIXES):
                protected.append(str(child))
    entry.update(size_bytes=size, apparent_bytes=apparent)
    if protected:
        return entry | {"reason": "contains protected content", "protected_paths": protected}
    return entry | {"eligible": True, "reason": "verified ignored generated cache"}


def process_kind(command, arguments):
    name = Path(command).name.lower()
    if name in BUILD_TOOLS or (name == "swift" and any(arg in {"build", "test"} for arg in arguments[1:3])):
        return "build"
    if name.startswith("sourcekit") or "indexstore" in name or name == "swift-ide-test":
        return "index"
    return None


def absolute_arguments(arguments):
    paths = []
    for argument in arguments:
        value = argument.split("=", 1)[-1] if "=" in argument else argument
        # Only path tokens count; sandbox profile text often embeds unrelated paths.
        if value.startswith("/") and not any(char in value for char in "\n\r\0"):
            paths.append(Path(value))
    return paths


def process_alive(pid, command=None):
    result = run(["ps", "-p", str(pid), "-o", "comm="])
    if result.returncode == 1 and not result.stdout.strip() and not result.stderr.strip():
        return False
    if result.returncode:
        return None
    return bool(result.stdout.strip()) if command is None else Path(result.stdout.strip()).name == Path(command).name


def activity_probe(worktree, candidate, package=None):
    """Return safe/reasons using actual process cwd, open files and path arguments."""
    try:
        if not shutil.which("ps") or not shutil.which("lsof"):
            return {"safe": False, "reasons": ["ps or lsof is unavailable"]}
        snapshot = run(["ps", "-axo", "pid=,comm="])
        if snapshot.returncode or snapshot.stderr.strip():
            return {"safe": False, "reasons": ["process inventory failed: " + snapshot.stderr.strip()]}
        processes = {}
        commands = {}
        for line in snapshot.stdout.splitlines():
            fields = line.strip().split(None, 1)
            if len(fields) != 2 or not fields[0].isdigit():
                return {"safe": False, "reasons": ["process inventory could not be parsed"]}
            pid, command = int(fields[0]), fields[1]
            commands[pid] = command
            if not process_kind(command, []) and Path(command).name.lower() != "swift":
                continue
            command_line = run(["ps", "-p", str(pid), "-o", "args="])
            try:
                arguments = shlex.split(command_line.stdout) if not command_line.returncode and not command_line.stderr else []
            except ValueError:
                arguments = []
            kind = process_kind(command, arguments) if arguments else "unknown"
            if kind:
                processes[pid] = (command, arguments, kind)
        opened = run(["lsof", "-nP", "-F", "pfn"])
        if opened.returncode or opened.stderr.strip():
            return {"safe": False, "reasons": ["open-file inventory failed: " + opened.stderr.strip()]}
        records = {}
        pid = descriptor = None
        for line in opened.stdout.splitlines():
            if line.startswith("p") and line[1:].isdigit():
                pid = int(line[1:])
                records[pid] = {"cwd": None, "paths": []}
            elif line.startswith("f"):
                descriptor = line[1:]
            elif line.startswith("n") and pid in records and line[1:].startswith("/"):
                path = Path(line[1:].removesuffix(" (deleted)"))
                records[pid]["paths"].append(path)
                if descriptor == "cwd":
                    records[pid]["cwd"] = path
        reasons = []
        alive_states = {}
        for pid, record in records.items():
            if any(inside(path, candidate) for path in record["paths"]):
                alive_states[pid] = process_alive(pid, commands.get(pid))
                if alive_states[pid] is not False:
                    reasons.append(f"process {pid} ({commands.get(pid, 'unknown command')}) has files open in {candidate}")
        for pid, (command, arguments, kind) in processes.items():
            alive = alive_states[pid] if pid in alive_states else process_alive(pid, command)
            if alive is False:
                continue
            record = records.get(pid)
            if alive is None or not record or record["cwd"] is None or not arguments:
                reasons.append(f"live process {pid} ({command}) could not be fully inspected")
                continue
            argument_paths = absolute_arguments(arguments)
            paths = record["paths"] + argument_paths
            if kind == "build" and any(inside(path, worktree) for path in paths):
                reasons.append(f"active build/test process {pid} ({command}) belongs to {worktree}")
            elif kind == "build" and record["cwd"] == Path("/"):
                reasons.append(f"live build/test process {pid} ({command}) has unresolved ownership with cwd /")
            elif kind == "index":
                affected = package or candidate
                index_paths = [path for path in record["paths"] if path != record["cwd"]] + argument_paths
                if any(inside(path, affected) for path in index_paths):
                    reasons.append(f"index process {pid} ({command}) references {affected} in open files or arguments")
        return {"safe": not reasons, "reasons": reasons}
    except (OSError, subprocess.SubprocessError) as error:
        return {"safe": False, "reasons": [f"activity inspection failed: {error}"]}


def disk_space(worktree):
    try:
        usage = shutil.disk_usage(worktree)
        return {"path": str(worktree), "total_bytes": usage.total, "used_bytes": usage.used, "available_bytes": usage.free}
    except OSError as error:
        return {"path": str(worktree), "error": str(error)}


def process_target(mode, worktree, probe):
    target = {"worktree": str(worktree), "status": "retained", "reason": "source worktree preserved", "paths": []}
    try:
        verify_worktree(worktree)
        candidates, target["paths"] = candidate_paths(worktree)
    except ValueError as error:
        return target | {"reason": str(error)}
    except (OSError, RuntimeError) as error:
        return target | {"status": "failed", "reason": str(error)}
    for path, package in candidates:
        try:
            entry = inspect_candidate(worktree, path)
            if entry.get("eligible"):
                activity = probe(worktree, path, package)
                entry["activity"] = activity
                if not activity["safe"]:
                    entry["reason"] = "; ".join(activity["reasons"])
                elif mode == "inspect":
                    entry["reason"] = "inspection only; eligible generated cache"
                else:
                    verify_worktree(worktree)
                    entry = inspect_candidate(worktree, path)
                    if entry.get("eligible"):
                        activity = probe(worktree, path, package)
                        entry["activity"] = activity
                        if not activity["safe"]:
                            entry["reason"] = "; ".join(activity["reasons"])
                        else:
                            shutil.rmtree(path)
                            if os.path.lexists(path):
                                entry.update(status="recreated", reason="cache path exists again after removal; left intact")
                            else:
                                entry.update(status="removed", reason="verified exact cache path is absent after removal")
            target["paths"].append(entry)
        except (OSError, RuntimeError, ValueError) as error:
            target["paths"].append({"path": str(path), "status": "failed", "reason": str(error), "size_bytes": None, "apparent_bytes": None})
    return target


def report(mode, worktrees, probe=None):
    paths = list(dict.fromkeys(Path(path) for path in worktrees))
    before = [disk_space(path) for path in paths]
    targets = [process_target(mode, path, probe or activity_probe) for path in paths]
    after = [disk_space(path) for path in paths]
    outcomes = [entry for target in targets for entry in (target["paths"] or [target])]
    counts = Counter(entry["status"] for entry in outcomes)
    return {"mode": mode, "targets": targets, "counts": {status: counts[status] for status in STATUSES},
            "disk_before": before, "disk_after": after,
            "available_change_bytes": [end["available_bytes"] - start["available_bytes"]
                                       if "available_bytes" in start and "available_bytes" in end else None
                                       for start, end in zip(before, after)]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("inspect", "clean"))
    parser.add_argument("--worktree", action="append", required=True)
    args = parser.parse_args()
    if not all(Path(path).is_absolute() for path in args.worktree):
        parser.error("--worktree requires an absolute path")
    result = report(args.mode, args.worktree)
    print(json.dumps(result, indent=2))
    return 1 if result["counts"]["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
