#!/usr/bin/env python3
"""Disposable Git fixtures and simulated simctl; never touches real devices."""

import contextlib
import copy
from datetime import datetime, timedelta, timezone
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import shlex
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[4]
spec = importlib.util.spec_from_file_location("simulators", ROOT / "scripts/worktree-simulators.py")
sim = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sim)
UID = "11111111-1111-4111-8111-111111111111"
SECOND = "22222222-2222-4222-8222-222222222222"
THIRD = "33333333-3333-4333-8333-333333333333"
FOURTH = "44444444-4444-4444-8444-444444444444"


class SimulatorCleanupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / "repo"
        self.repo.mkdir()
        self.git("init", "-q")
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@localhost",
                 "commit", "-q", "--allow-empty", "-m", "fixture")
        self.target = self.repo / ".claude/worktrees/task"
        self.other = self.repo / ".worktrees/other"
        self.git("worktree", "add", "-q", "--detach", str(self.target))
        self.git("worktree", "add", "-q", "--detach", str(self.other))
        self.state = {UID: {"udid": UID, "name": "custom repro", "state": "Booted",
                            "runtime": "com.apple.CoreSimulator.SimRuntime.iOS-27-0"}}
        self.calls = []
        leases = patch.object(sim, "LEASES", Path(self.temp.name) / "state/simulator-leases.json")
        leases.start()
        self.addCleanup(leases.stop)

    def device(self, udid, name, last_used, kind="iPhone-17-Pro", runtime="iOS-27-0"):
        self.state[udid] = {"udid": udid, "name": name, "state": "Shutdown", "isAvailable": True,
                            "lastUsedAt": last_used,
                            "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType." + kind,
                            "runtime": "com.apple.CoreSimulator.SimRuntime." + runtime}

    def lease(self, udid, owner, hours_ago=0, slot="default"):
        leases = sim.read_leases()
        renewed = datetime.now(timezone.utc) - timedelta(hours=hours_ago)
        leases[udid] = {"owner": str(owner.resolve()), "slot": slot,
                        "renewed_at": renewed.isoformat(timespec="seconds")}
        sim.LEASES.parent.mkdir(parents=True, exist_ok=True)
        sim.LEASES.write_text(json.dumps(leases))

    def leased_to(self, owner, slot="default"):
        return [u for u, lease in sim.read_leases().items()
                if lease["owner"] == str(owner.resolve()) and lease["slot"] == slot]

    def git(self, *args):
        subprocess.run(["git", "-C", str(self.repo), *args], check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def register(self, root, udid=UID, name="sim-udid"):
        path = root / ".claude" / name
        path.parent.mkdir(exist_ok=True)
        path.write_text(udid)
        return path

    def act(self, action, *options, owner=None, failure=False, unchanged=False):
        real_run = subprocess.run

        def mutate(args, **kwargs):
            if args[0] != "xcrun":
                return real_run(args, **kwargs)
            self.calls.append(args)
            if failure:
                raise subprocess.CalledProcessError(1, args)
            if not unchanged:
                if args[2] == "boot":
                    self.state[args[3]]["state"] = "Booted"
                elif args[2] == "shutdown":
                    self.state[args[3]]["state"] = "Shutdown"
                else:
                    self.state.pop(args[3])
            return subprocess.CompletedProcess(args, 0, "", "")
        args = ["helper", action, "--worktree", str(owner or self.target), *options]
        with patch.object(sys, "argv", args), patch.object(sim, "devices", lambda: copy.deepcopy(self.state)), \
                patch.object(sim.subprocess, "run", mutate), contextlib.redirect_stdout(io.StringIO()), \
                contextlib.redirect_stderr(io.StringIO()):
            return sim.main()

    def test_inspection_is_read_only_and_claude_worktree_is_supported(self):
        path = self.register(self.target)
        self.assertEqual(self.act("inspect"), 0)
        self.assertEqual(self.calls, [])
        self.assertTrue(path.exists())

    def test_shell_resolves_claude_and_nested_worktrees(self):
        nested = self.target / ".subworktrees/nested"
        self.git("worktree", "add", "-q", "--detach", str(nested))
        for root in [self.target, nested]:
            with self.subTest(root=root):
                result = subprocess.run(["bash", str(ROOT / "scripts/worktree-sim.sh"), "invalid"],
                                        cwd=root, capture_output=True, text=True)
                self.assertEqual(result.returncode, 64, result.stderr)
                self.assertNotIn("not in a registered", result.stderr)

    def test_default_deletes_all_registered_runtime_variants(self):
        first = self.register(self.target)
        second = self.register(self.target, SECOND, "sim-udid-ios27-1")
        self.state[SECOND] = dict(self.state[UID], udid=SECOND, state="Shutdown")
        self.assertEqual(self.act("delete"), 0)
        self.assertEqual(self.state, {})
        self.assertFalse(first.exists())
        self.assertFalse(second.exists())

    def test_runtime_scope_preserves_other_variants(self):
        default = self.register(self.target)
        scoped = self.register(self.target, SECOND, "sim-udid-ios27-1")
        self.state[SECOND] = dict(self.state[UID], udid=SECOND, state="Shutdown")
        self.assertEqual(self.act("delete", "--suffix", "ios27-1"), 0)
        self.assertTrue(default.exists())
        self.assertFalse(scoped.exists())
        self.assertIn(UID, self.state)

    def test_shared_registration_is_retained_even_for_primary_checkout(self):
        self.register(self.target)
        self.register(self.repo)
        self.assertEqual(self.act("delete"), 1)
        self.assertEqual(self.calls, [])
        self.assertIn(UID, self.state)

    def test_shared_device_within_deletion_group_is_removed_once(self):
        first = self.register(self.target)
        second = self.register(self.other)
        self.assertEqual(self.act("delete", "--worktree", str(self.other)), 0)
        self.assertFalse(first.exists())
        self.assertFalse(second.exists())
        self.assertEqual(sum(args[2] == "delete" for args in self.calls), 1)

    def test_delete_failure_keeps_registration(self):
        path = self.register(self.target)
        with self.assertRaises(subprocess.CalledProcessError):
            self.act("delete", failure=True)
        self.assertTrue(path.exists())

    def test_success_exit_without_device_removal_is_failure(self):
        path = self.register(self.target)
        self.state[UID]["state"] = "Shutdown"
        with self.assertRaises(RuntimeError):
            self.act("delete", unchanged=True)
        self.assertTrue(path.exists())

    def test_stale_registration_removed_without_device_command(self):
        path = self.register(self.target)
        self.state.clear()
        self.assertEqual(self.act("delete"), 0)
        self.assertFalse(path.exists())
        self.assertEqual(self.calls, [])

    def test_generated_name_requires_explicit_inclusion(self):
        self.state[UID]["name"] = "sim-task"
        self.assertEqual(self.act("delete"), 1)
        self.assertEqual(self.calls, [])
        self.assertEqual(self.act("delete", "--include-named"), 0)

    def test_ambiguous_generated_name_stays_retained(self):
        duplicate = self.repo / ".worktrees/task"
        self.git("worktree", "add", "-q", "--detach", str(duplicate))
        self.state[UID]["name"] = "sim-task"
        self.assertEqual(self.act("delete", "--include-named"), 1)
        self.assertEqual(self.calls, [])

    def test_shutdown_retains_registration(self):
        path = self.register(self.target)
        self.assertEqual(self.act("shutdown"), 0)
        self.assertEqual(self.state[UID]["state"], "Shutdown")
        self.assertTrue(path.exists())

    def test_ensure_leases_most_recent_free_iphone_and_keeps_it(self):
        self.device(SECOND, "iPhone 17 Pro", "2026-10-27T00:00:00Z")
        self.device(THIRD, "iPhone Duo", "2026-10-28T03:00:00Z", kind="iPhone-Duo")
        self.device(FOURTH, "iPad Pro", "2026-10-28T09:00:00Z", kind="iPad-Pro-11-inch-M5-12GB")
        self.state[UID].update(self.state[SECOND], udid=UID, name="sim-task", lastUsedAt="2026-10-28T09:00:00Z")
        self.assertEqual(self.act("ensure"), 0)
        self.assertEqual(self.leased_to(self.target), [THIRD])
        self.assertEqual(self.state[THIRD]["state"], "Booted")
        self.state[SECOND]["lastUsedAt"] = "2026-10-28T10:00:00Z"
        self.assertEqual(self.act("ensure"), 0)
        self.assertEqual(self.leased_to(self.target), [THIRD])

    def test_ensure_skips_live_leases_and_takes_over_expired_ones(self):
        self.device(SECOND, "iPhone 17 Pro", "2026-10-28T03:00:00Z")
        self.device(THIRD, "iPhone 17", "2026-10-27T00:00:00Z")
        self.lease(SECOND, self.other)
        self.assertEqual(self.act("ensure"), 0)
        self.assertEqual(self.leased_to(self.target), [THIRD])
        self.lease(THIRD, self.other, hours_ago=3)
        self.assertEqual(self.act("ensure", owner=self.repo), 0)
        self.assertEqual(self.leased_to(self.repo), [THIRD])
        self.assertEqual(self.leased_to(self.other), [SECOND])

    def test_ensure_without_free_device_fails_instead_of_creating(self):
        self.device(SECOND, "iPhone 17 Pro", "2026-10-28T03:00:00Z")
        self.lease(SECOND, self.other)
        with self.assertRaises(sim.NoSimulator):
            self.act("ensure")
        self.assertEqual(self.calls, [])

    def test_runtime_lease_coexists_with_default_lease(self):
        self.device(SECOND, "iPhone 17 Pro", "2026-10-28T03:00:00Z")
        self.device(THIRD, "iPhone 16 Pro", "2026-10-01T00:00:00Z", runtime="iOS-18-6")
        self.assertEqual(self.act("ensure"), 0)
        self.assertEqual(self.act("ensure", "--runtime", "iOS-18-6"), 0)
        self.assertEqual(self.leased_to(self.target), [SECOND])
        self.assertEqual(self.leased_to(self.target, "iOS-18-6"), [THIRD])
        self.assertEqual(self.act("delete", "--suffix", "ios18-6"), 0)
        self.assertEqual(sim.read_leases().keys(), {SECOND})

    def test_cleanup_releases_lease_without_touching_device(self):
        self.device(SECOND, "iPhone 17 Pro", "2026-10-28T03:00:00Z")
        self.lease(SECOND, self.target)
        self.assertEqual(self.act("delete"), 0)
        self.assertEqual(self.calls, [])
        self.assertIn(SECOND, self.state)
        self.assertEqual(sim.read_leases(), {})

    def test_release_preserves_legacy_device_and_other_worktree_lease(self):
        registration = self.register(self.target)
        self.lease(SECOND, self.target)
        self.lease(THIRD, self.other)
        before = copy.deepcopy(self.state)
        self.assertEqual(self.act("release"), 0)
        self.assertEqual(self.leased_to(self.target), [])
        self.assertEqual(self.leased_to(self.other), [THIRD])
        self.assertEqual(self.calls, [])
        self.assertEqual(self.state, before)
        self.assertEqual(registration.read_text(), UID)

    def test_registered_device_leased_elsewhere_is_retained(self):
        self.register(self.target)
        self.lease(UID, self.other)
        self.assertEqual(self.act("delete"), 1)
        self.assertEqual(self.calls, [])
        self.assertIn(UID, self.state)
        self.assertEqual(self.leased_to(self.other), [UID])


class DerivedDataCleanupTests(unittest.TestCase):
    def test_supported_layouts_delete_only_matching_workspace(self):
        source = (ROOT / "core/skills/cleanup-and-exit/scripts/remove-worktree-derived-data.sh").read_text()
        original = 'derived_data_root="${HOME:?}/Library/Developer/Xcode/DerivedData"'
        self.assertEqual(source.count(original), 1)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cache = root / "cache"
            cache.mkdir()
            # Redirect just the cache root; the real shell helper and plutil run unchanged.
            script = source.replace(original, "derived_data_root=" + shlex.quote(str(cache)))
            for layout in [".worktrees", ".claude/worktrees", ".codex/worktrees"]:
                with self.subTest(layout=layout):
                    target = root / layout / "task"
                    matching, similar = cache / "matching", cache / "similar"
                    for path, workspace in [(matching, target / "Example.xcworkspace"),
                                            (similar, Path(str(target) + "-other") / "Example.xcworkspace")]:
                        path.mkdir(exist_ok=True)
                        with (path / "info.plist").open("wb") as stream:
                            plistlib.dump({"WorkspacePath": str(workspace)}, stream)
                    result = subprocess.run(["bash", "-s", "--", str(target)], input=script,
                                            text=True, capture_output=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertFalse(matching.exists())
                    self.assertTrue(similar.exists())
                    target.mkdir(parents=True)
                    result = subprocess.run(["bash", "-s", "--", str(target)], input=script,
                                            text=True, capture_output=True)
                    self.assertEqual(result.returncode, 4)
                    self.assertTrue(similar.exists())


if __name__ == "__main__":
    unittest.main()
