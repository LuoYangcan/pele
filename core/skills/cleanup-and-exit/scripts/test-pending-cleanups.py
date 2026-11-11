#!/usr/bin/env python3
"""Exercise pending-cleanup metadata using disposable local Git repositories."""

import errno
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).with_name("pending-cleanups.py")
SPEC = importlib.util.spec_from_file_location("pending_cleanups", SCRIPT)
pending = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pending)


class PendingCleanupTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name).resolve()
        self.repo = self.base / "repo"
        self.create_repo(self.repo)
        self.target = self.add_worktree("task")
        self.other = self.add_worktree("other")
        self.common = self.repo / ".git"
        self.state = self.common / "cleanup-and-exit" / "pending.json"

    def git(self, *args, repo=None):
        return subprocess.check_output(["git", "-C", str(repo or self.repo), *args],
                                       text=True, stderr=subprocess.PIPE).strip()

    def create_repo(self, path):
        path.mkdir()
        self.git("init", "-q", repo=path)
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@localhost",
                 "commit", "-q", "--allow-empty", "-m", "fixture", repo=path)

    def add_worktree(self, name, detached=False):
        path = self.base / name
        options = ["--detach"] if detached else ["-b", name]
        self.git("worktree", "add", "-q", *options, str(path))
        return path

    def call(self, *args, success=True):
        result = subprocess.run([sys.executable, str(SCRIPT), *map(str, args)],
                                text=True, capture_output=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(result.stdout)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def add(self, path=None, *options, success=True):
        return self.call("add", "--worktree", path or self.target, "--reason", "PR still open",
                         *options, success=success)

    def listing(self, repo=None, success=True):
        return self.call("list", "--repo", repo or self.repo, success=success)

    def remove(self, path=None, success=True):
        return self.call("remove", "--repo", self.repo, "--worktree", path or self.target,
                         success=success)

    def snapshot(self):
        return {str(path.relative_to(self.common)):
                (path.stat().st_mtime_ns, path.read_bytes() if path.is_file() else None)
                for path in self.common.rglob("*")}

    def test_absent_list_does_not_create_or_modify_metadata(self):
        before = self.snapshot()
        result = self.listing()
        self.assertEqual(result["entries"], [])
        self.assertEqual(result["state_path"], str(self.state))
        self.assertFalse(self.state.parent.exists())
        self.assertEqual(self.snapshot(), before)

    def test_add_list_remove_are_idempotent_and_list_is_read_only(self):
        self.assertEqual(self.add(self.target, "--pr", "https://example.test/pull/1")["status"], "added")
        self.assertEqual(self.add(self.target, "--pr", "https://example.test/pull/1")["status"], "updated")
        before = self.snapshot()
        rows = self.listing()["entries"]
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(len(rows), 1)
        row = rows[0]
        self.assertEqual(row["worktree"], str(self.target))
        self.assertEqual(row["branch"], "refs/heads/task")
        self.assertEqual(row["pr"], "https://example.test/pull/1")
        self.assertEqual(row["inspection"]["identity_status"], "match")
        self.assertEqual(row["inspection"]["current_head"], row["queued_head"])
        self.assertEqual(self.state.parent.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.state.stat().st_mode & 0o777, 0o600)
        self.add()
        self.assertEqual(self.listing()["entries"][0]["pr"], row["pr"])
        self.assertEqual(self.remove()["status"], "removed")
        before = self.state.read_bytes()
        self.assertEqual(self.remove()["status"], "not_queued")
        self.assertEqual(self.state.read_bytes(), before)
        self.assertTrue(self.target.is_dir())
        self.assertIn(self.target, pending.registered_worktrees(self.repo))

    def test_detached_worktree_is_recorded(self):
        detached = self.add_worktree("detached", detached=True)
        self.add(detached)
        row = self.listing()["entries"][0]
        self.assertEqual(row["branch"], "detached")
        self.assertEqual(row["inspection"]["identity_status"], "match")

    def test_entries_survive_worktree_removal(self):
        self.add()
        before = self.state.read_bytes()
        self.git("worktree", "remove", str(self.target))
        row = self.listing()["entries"][0]
        self.assertEqual(row["inspection"]["identity_status"], "absent")
        self.assertIsNone(row["inspection"]["current_head"])
        self.assertEqual(self.state.read_bytes(), before)

    def test_missing_directory_with_registration_is_stale(self):
        self.add()
        shutil.rmtree(self.target)
        row = self.listing()["entries"][0]
        self.assertEqual(row["inspection"]["identity_status"], "stale_registration")

    def test_branch_change_is_detected_and_add_does_not_replace_old_identity(self):
        self.add()
        before = self.state.read_bytes()
        self.git("switch", "-q", "-c", "another-task", repo=self.target)
        row = self.listing()["entries"][0]
        self.assertEqual(row["inspection"]["identity_status"], "changed")
        self.assertEqual(row["inspection"]["current_branch"], "refs/heads/another-task")
        self.assertIn("identity changed", self.add(success=False).stderr)
        self.assertEqual(self.state.read_bytes(), before)

    def test_reusing_same_path_and_branch_is_detected(self):
        self.add()
        before = self.state.read_bytes()
        self.git("worktree", "remove", str(self.target))
        self.git("worktree", "add", "-q", str(self.target), "task")
        row = self.listing()["entries"][0]
        self.assertEqual(row["inspection"]["identity_status"], "changed")
        self.add(success=False)
        self.assertEqual(self.state.read_bytes(), before)

    def test_new_head_on_same_branch_is_still_the_same_task_identity(self):
        self.add()
        queued = self.listing()["entries"][0]["queued_head"]
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@localhost",
                 "commit", "-q", "--allow-empty", "-m", "later work", repo=self.target)
        row = self.listing()["entries"][0]
        self.assertEqual(row["inspection"]["identity_status"], "match")
        self.assertNotEqual(row["inspection"]["current_head"], queued)
        self.add()
        self.assertEqual(self.listing()["entries"][0]["queued_head"], row["inspection"]["current_head"])

    def test_primary_subdirectory_relative_path_and_symlink_alias_are_rejected(self):
        subdirectory = self.target / "subdirectory"
        subdirectory.mkdir()
        alias = self.base / "alias"
        alias.symlink_to(self.target, target_is_directory=True)
        for path in (self.repo, subdirectory, Path("."), alias):
            with self.subTest(path=path):
                self.add(path, success=False)
        self.assertFalse(self.state.exists())

    def test_replaced_symlink_path_is_changed(self):
        self.add()
        self.git("worktree", "remove", str(self.target))
        self.target.symlink_to(self.other, target_is_directory=True)
        self.assertEqual(self.listing()["entries"][0]["inspection"]["identity_status"], "changed")

    def test_foreign_common_dir_or_git_dir_state_is_rejected(self):
        self.add()
        foreign = self.base / "foreign"
        self.create_repo(foreign)
        path = foreign / ".git/cleanup-and-exit/pending.json"
        path.parent.mkdir()
        path.write_bytes(self.state.read_bytes())
        self.listing(foreign, success=False)
        data = json.loads(path.read_text())
        data["common_dir"] = str(foreign / ".git")
        path.write_text(json.dumps(data))
        result = self.listing(foreign, success=False)
        self.assertIn("different repository", result.stderr)

    def test_malformed_json_is_not_discarded_by_any_action(self):
        self.state.parent.mkdir()
        self.state.write_text("{broken")
        before = self.state.read_bytes()
        self.listing(success=False)
        self.add(success=False)
        self.remove(success=False)
        self.assertEqual(self.state.read_bytes(), before)

    def test_malformed_entry_prevents_updates_and_is_not_pruned(self):
        self.add()
        original = self.state.read_text()
        for field, value in (("worktree", "relative/path"), ("branch", "refs/heads/.."),
                             ("updated_at", "2026-01-01Z"), ("pr", "not a URL"),
                             ("git_dir_identity", {"device": 1, "inode": "bad"})):
            with self.subTest(field=field):
                data = json.loads(original)
                data["entries"][0][field] = value
                self.state.write_text(json.dumps(data))
                before = self.state.read_bytes()
                self.listing(success=False)
                self.add(self.other, success=False)
                self.remove(success=False)
                self.assertEqual(self.state.read_bytes(), before)

    def test_updates_and_remove_preserve_unrelated_entries(self):
        self.add()
        self.add(self.other)
        other_entry = next(row for row in json.loads(self.state.read_text())["entries"]
                           if row["worktree"] == str(self.other))
        self.add()
        self.remove()
        self.assertEqual(json.loads(self.state.read_text())["entries"], [other_entry])
        self.remove(self.base / "not-queued")
        self.assertEqual(json.loads(self.state.read_text())["entries"], [other_entry])

    def test_concurrent_adds_preserve_all_entries(self):
        targets = [self.target, self.other, *[self.add_worktree(f"parallel-{n}") for n in range(6)]]
        processes = [subprocess.Popen([sys.executable, str(SCRIPT), "add", "--worktree", str(path),
                                       "--reason", "deferred"], text=True,
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                     for path in targets]
        for process in processes:
            stdout, stderr = process.communicate(timeout=15)
            self.assertEqual(process.returncode, 0, stderr or stdout)
        rows = self.listing()["entries"]
        self.assertEqual({row["worktree"] for row in rows}, set(map(str, targets)))

    def test_lock_timeout_and_unsupported_locking_fail_explicitly(self):
        for code, times, message in ((errno.EAGAIN, [0, 6], "timed out"),
                                      (errno.ENOTSUP, [0], "locking failed")):
            with self.subTest(code=code), \
                    patch("fcntl.flock", side_effect=OSError(code, "fixture")), \
                    patch.object(pending.time, "monotonic", side_effect=times):
                with self.assertRaisesRegex(RuntimeError, message):
                    with pending.locked_state(self.common):
                        self.fail("lock unexpectedly acquired")


if __name__ == "__main__":
    unittest.main()
