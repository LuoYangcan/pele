#!/usr/bin/env python3
"""Record deferred task cleanups; inspect or edit metadata without cleaning anything."""

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import errno
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
from urllib.parse import urlsplit


def git(path, *args):
    result = subprocess.run(["git", "-C", str(path), *args], text=True,
                            capture_output=True, env=dict(os.environ, GIT_OPTIONAL_LOCKS="0"))
    if result.returncode:
        raise ValueError(result.stderr.strip() or f"git {' '.join(args)} failed")
    return result.stdout.rstrip("\n")


def common_dir(repo):
    return Path(git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir")).resolve()


def registered_worktrees(repo):
    raw = git(repo, "worktree", "list", "--porcelain", "-z")
    return [Path(item[9:]) for item in raw.split("\0") if item.startswith("worktree ")]


def absolute_path(value):
    path = Path(value)
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError(f"expected an absolute normalized path: {value}")
    return path


def directory_identity(path):
    info = path.stat()
    return {"device": info.st_dev, "inode": info.st_ino}


def live_identity(worktree, common, roots):
    if worktree != worktree.resolve():
        raise ValueError(f"symlink aliases are not accepted: {worktree}")
    if worktree not in roots[1:]:
        raise ValueError(f"not a registered non-primary worktree: {worktree}")
    root = Path(git(worktree, "rev-parse", "--show-toplevel"))
    if root != worktree or common_dir(worktree) != common:
        raise ValueError(f"worktree root or repository changed: {worktree}")
    git_dir = Path(git(worktree, "rev-parse", "--absolute-git-dir")).resolve()
    if git_dir.parent != common / "worktrees":
        raise ValueError(f"unexpected linked-worktree git directory: {git_dir}")
    branch = git(worktree, "rev-parse", "--symbolic-full-name", "HEAD")
    return {"git_dir": str(git_dir), "git_dir_identity": directory_identity(git_dir),
            "branch": "detached" if branch == "HEAD" else branch,
            "queued_head": git(worktree, "rev-parse", "--verify", "HEAD")}


def state_path(common):
    return common / "cleanup-and-exit" / "pending.json"


def validate_entry(entry, common):
    required = {"worktree", "git_dir", "git_dir_identity", "branch", "queued_head",
                "reason", "updated_at"}
    if not isinstance(entry, dict) or not required <= entry.keys() or entry.keys() - required - {"pr"}:
        raise ValueError("malformed pending-cleanup entry fields")
    for key in required - {"git_dir_identity"}:
        if not isinstance(entry[key], str) or not entry[key].strip() or "\0" in entry[key]:
            raise ValueError(f"malformed pending-cleanup {key}")
    absolute_path(entry["worktree"])
    if absolute_path(entry["git_dir"]).parent != common / "worktrees":
        raise ValueError("pending-cleanup git directory belongs to a different repository")
    identity = entry["git_dir_identity"]
    if (not isinstance(identity, dict) or identity.keys() != {"device", "inode"}
            or any(type(value) is not int or value < 0 for value in identity.values())):
        raise ValueError("malformed pending-cleanup git directory identity")
    if not (entry["branch"] == "detached" or entry["branch"].startswith("refs/heads/")):
        raise ValueError("malformed pending-cleanup branch")
    if entry["branch"] != "detached":
        git(common, "check-ref-format", entry["branch"])
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", entry["queued_head"]):
        raise ValueError("malformed pending-cleanup queued HEAD")
    if not entry["updated_at"].endswith("Z"):
        raise ValueError("pending-cleanup updated_at must be UTC")
    if datetime.fromisoformat(entry["updated_at"][:-1] + "+00:00").tzinfo != timezone.utc:
        raise ValueError("malformed pending-cleanup updated_at")
    if "pr" in entry:
        if not isinstance(entry["pr"], str):
            raise ValueError("malformed pending-cleanup PR URL")
        url = urlsplit(entry["pr"])
        if url.scheme not in {"http", "https"} or not url.netloc:
            raise ValueError("malformed pending-cleanup PR URL")


def read_state(common):
    path = state_path(common)
    if path.parent.is_symlink() or path.is_symlink():
        raise ValueError(f"pending-cleanup metadata must not be a symlink: {path}")
    try:
        data = json.loads(path.read_text())
    except FileNotFoundError:
        return {"version": 1, "common_dir": str(common), "entries": []}
    if (not isinstance(data, dict) or data.keys() != {"version", "common_dir", "entries"}
            or type(data["version"]) is not int or data["version"] != 1
            or data["common_dir"] != str(common) or not isinstance(data["entries"], list)):
        raise ValueError(f"malformed or foreign pending-cleanup state: {path}")
    seen = set()
    for entry in data["entries"]:
        validate_entry(entry, common)
        if entry["worktree"] in seen:
            raise ValueError("duplicate pending-cleanup worktree entry")
        seen.add(entry["worktree"])
    return data


@contextmanager
def locked_state(common):
    try:
        import fcntl
    except ImportError as error:
        raise RuntimeError("pending-cleanup updates require POSIX file locking") from error
    folder = state_path(common).parent
    if folder.is_symlink():
        raise ValueError(f"pending-cleanup metadata must not be a symlink: {folder}")
    folder.mkdir(mode=0o700, exist_ok=True)
    folder.chmod(0o700)
    with os.fdopen(os.open(folder / ".lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600), "r+") as lock:
        deadline = time.monotonic() + 5
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError as error:
                if error.errno not in {errno.EACCES, errno.EAGAIN}:
                    raise RuntimeError("pending-cleanup POSIX locking failed") from error
                if time.monotonic() >= deadline:
                    raise RuntimeError("timed out waiting for pending-cleanup metadata lock") from error
                time.sleep(0.05)
        yield read_state(common)


def write_state(common, data):
    path = state_path(common)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, prefix=".pending-", delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(data, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def inspect_entry(entry, common, roots):
    path = Path(entry["worktree"])
    inspection = {"current_branch": None, "current_head": None}
    if not path.exists() and not path.is_symlink():
        inspection["identity_status"] = "stale_registration" if path in roots else "absent"
        return inspection
    try:
        current = live_identity(path, common, roots)
        inspection.update(current_branch=current["branch"], current_head=current["queued_head"])
        identity_fields = ("git_dir", "git_dir_identity", "branch")
        inspection["identity_status"] = (
            "match" if all(current[key] == entry[key] for key in identity_fields) else "changed")
    except (OSError, ValueError) as error:
        inspection.update(identity_status="changed", error=str(error))
    return inspection


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    listing = commands.add_parser("list")
    listing.add_argument("--repo", type=Path, required=True)
    adding = commands.add_parser("add")
    adding.add_argument("--worktree", required=True)
    adding.add_argument("--reason", required=True)
    adding.add_argument("--pr")
    removing = commands.add_parser("remove")
    removing.add_argument("--repo", type=Path, required=True)
    removing.add_argument("--worktree", required=True)
    args = parser.parse_args(argv)
    common = common_dir(args.worktree if args.action == "add" else args.repo)
    result = {"state_path": str(state_path(common))}
    if args.action == "list":
        data = read_state(common)
        roots = registered_worktrees(args.repo)
        result["entries"] = [dict(entry, inspection=inspect_entry(entry, common, roots))
                             for entry in data["entries"]]
    else:
        worktree = absolute_path(args.worktree)
        with locked_state(common) as data:
            existing = next((entry for entry in data["entries"] if entry["worktree"] == str(worktree)), None)
            if args.action == "add":
                identity = live_identity(worktree, common, registered_worktrees(worktree))
                if existing and any(existing[key] != identity[key]
                                    for key in ("git_dir", "git_dir_identity", "branch")):
                    raise ValueError("queued worktree identity changed; inspect and remove its old entry before adding")
                entry = dict(identity, worktree=str(worktree), reason=args.reason,
                             updated_at=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"))
                if args.pr is not None:
                    entry["pr"] = args.pr
                elif existing is not None and "pr" in existing:
                    entry["pr"] = existing["pr"]
                validate_entry(entry, common)
                if existing is not None:
                    data["entries"][data["entries"].index(existing)] = entry
                else:
                    data["entries"].append(entry)
                result["status"] = "updated" if existing else "added"
                write_state(common, data)
            elif existing is not None:
                data["entries"].remove(existing)
                write_state(common, data)
                result["status"] = "removed"
            else:
                result["status"] = "not_queued"
        result["entries"] = data["entries"]
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
