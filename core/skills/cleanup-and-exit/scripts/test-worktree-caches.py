#!/usr/bin/env python3
"""Disposable Git fixtures; these tests never inspect or clean live caches."""

import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("worktree_caches", Path(__file__).with_name("worktree-caches.py"))
caches = importlib.util.module_from_spec(spec)
spec.loader.exec_module(caches)


def inactive(*_):
    return {"safe": True, "reasons": []}


def result(stdout="", returncode=0, stderr=""):
    return subprocess.CompletedProcess([], returncode, stdout, stderr)


class CacheTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name).resolve()
        self.primary = self.base / "repo"
        self.primary.mkdir()
        self.command(self.primary, "init", "--initial-branch=main")
        (self.primary / ".gitignore").write_text("build/\nDerivedData/\n.build/\nPackage/.build/\n")
        (self.primary / "Package.swift").write_text("// root package\n")
        (self.primary / "Source.swift").write_text("let original = 1\n")
        (self.primary / "Package").mkdir()
        (self.primary / "Package/Package.swift").write_text("// nested package\n")
        self.command(self.primary, "add", ".")
        self.command(self.primary, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-m", "fixture")
        self.worktree = self.base / "linked"
        self.command(self.primary, "worktree", "add", "-b", "feature", str(self.worktree))

    def command(self, root, *args):
        return subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True, text=True).stdout

    def cache(self, relative="build/DerivedData/Build/Products"):
        directory = self.worktree / relative
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "generated.bin").write_bytes(b"generated" * 1024)
        return directory

    def entry(self, report, path):
        return next(entry for entry in report["targets"][0]["paths"] if entry["path"] == str(path))

    def test_inspection_is_read_only(self):
        directory = self.cache()
        before = self.command(self.worktree, "status", "--porcelain")
        with patch.object(caches.shutil, "rmtree", side_effect=AssertionError("inspection mutated a cache")):
            report = caches.report("inspect", [self.worktree], inactive)
        self.assertTrue(directory.exists())
        self.assertTrue(self.entry(report, directory)["eligible"])
        self.assertEqual(before, self.command(self.worktree, "status", "--porcelain"))
        self.assertEqual(report["counts"]["removed"], 0)

    def test_dirty_source_and_task_records_survive_cache_cleanup(self):
        directory = self.cache()
        source = self.worktree / "Source.swift"
        source.write_text("let changed = 2\n")
        task = self.worktree / ".claude/task.json"
        task.parent.mkdir()
        task.write_text('{"unfinished": true}\n')
        before = self.command(self.worktree, "status", "--porcelain")
        report = caches.report("clean", [self.worktree], inactive)
        self.assertEqual(self.entry(report, directory)["status"], "removed")
        self.assertFalse(directory.exists())
        self.assertEqual(source.read_text(), "let changed = 2\n")
        self.assertTrue(task.exists())
        self.assertEqual(before, self.command(self.worktree, "status", "--porcelain"))
        self.assertEqual(self.command(self.worktree, "branch", "--show-current").strip(), "feature")

    def test_tracked_or_unignored_content_is_retained(self):
        tracked = self.cache()
        self.command(self.worktree, "add", "-f", str(tracked / "generated.bin"))
        report = caches.report("clean", [self.worktree], inactive)
        self.assertIn("tracked", self.entry(report, tracked)["reason"])
        self.assertTrue(tracked.exists())
        self.command(self.worktree, "reset", "--", str(tracked / "generated.bin"))
        (self.worktree / ".gitignore").unlink()
        report = caches.report("clean", [self.worktree], inactive)
        self.assertIn("not Git-ignored", self.entry(report, tracked)["reason"])
        self.assertTrue(tracked.exists())

    def test_only_allowlisted_package_children_are_cleaned(self):
        module = self.cache("Package/.build/arm64-apple-macosx/debug/ModuleCache")
        index = self.cache("Package/.build/index-build/arm64-apple-macosx/release/index")
        products = self.cache("Package/.build/arm64-apple-macosx/debug/Products")
        checkout = self.cache("Package/.build/checkouts/dependency")
        artifacts = self.cache("Package/.build/artifacts/dependency")
        untracked_package = self.cache("Untracked/.build/arm64-apple-macosx/debug/ModuleCache")
        (self.worktree / "Untracked/Package.swift").write_text("// untracked package\n")
        report = caches.report("clean", [self.worktree], inactive)
        self.assertEqual(self.entry(report, module)["status"], "removed")
        self.assertEqual(self.entry(report, index)["status"], "removed")
        for directory in (products, checkout, artifacts, untracked_package, module.parent, self.worktree / "Package/.build"):
            self.assertTrue(directory.exists(), str(directory))

    def test_nested_repositories_and_results_are_retained(self):
        for name in (".git", "tests.xcresult", "product.xcarchive"):
            with self.subTest(name=name):
                directory = self.cache()
                protected = directory / name
                protected.mkdir()
                (protected / "content").write_text("preserve\n")
                report = caches.report("clean", [self.worktree], inactive)
                self.assertEqual(self.entry(report, directory)["status"], "retained")
                self.assertTrue(protected.exists())
                shutil.rmtree(protected)

    def test_compiled_test_products_are_rebuildable(self):
        directory = self.cache()
        bundle = directory / "Debug/AppTests.xctest"
        bundle.mkdir(parents=True)
        (bundle / "AppTests").write_bytes(b"compiled test executable")
        report = caches.report("clean", [self.worktree], inactive)
        self.assertEqual(self.entry(report, directory)["status"], "removed")

    def test_target_and_ancestor_symlinks_retain_but_product_links_can_be_removed(self):
        shared = self.base / "shared"
        shared.mkdir()
        (shared / "valuable").write_text("keep\n")
        directory = self.worktree / "DerivedData/ModuleCache.noindex"
        directory.parent.mkdir()
        directory.symlink_to(shared, target_is_directory=True)
        report = caches.report("clean", [self.worktree], inactive)
        self.assertEqual(self.entry(report, directory)["status"], "retained")
        self.assertTrue(directory.is_symlink())
        directory.unlink()
        directory.parent.rmdir()
        directory.parent.symlink_to(shared, target_is_directory=True)
        report = caches.report("clean", [self.worktree], inactive)
        self.assertEqual(self.entry(report, directory)["status"], "retained")
        self.assertTrue((shared / "valuable").exists())
        local = self.cache()
        framework = local / "Fixture.framework/Versions/A"
        framework.mkdir(parents=True)
        (framework / "Fixture").write_bytes(b"compiled framework")
        (framework.parent / "Current").symlink_to("A", target_is_directory=True)
        (local / "shared").symlink_to(shared, target_is_directory=True)
        report = caches.report("clean", [self.worktree], inactive)
        self.assertEqual(self.entry(report, local)["status"], "removed")
        self.assertFalse(local.exists())
        self.assertTrue((shared / "valuable").exists())

    def test_primary_worktree_is_denied(self):
        directory = self.primary / "build/DerivedData/Build/Products"
        directory.mkdir(parents=True)
        report = caches.report("clean", [self.primary], inactive)
        self.assertIn("primary", report["targets"][0]["reason"])
        self.assertEqual(report["counts"]["retained"], 1)
        self.assertTrue(directory.exists())

    def test_probe_failure_and_last_moment_activity_retain_cache(self):
        directory = self.cache()
        blocked = {"safe": False, "reasons": ["activity probe unavailable"]}
        report = caches.report("clean", [self.worktree], lambda *_: blocked)
        self.assertEqual(self.entry(report, directory)["status"], "retained")
        self.assertTrue(directory.exists())
        probes = iter((inactive(), {"safe": False, "reasons": ["new build owns this worktree"]}))
        report = caches.report("clean", [self.worktree], lambda *_: next(probes))
        self.assertIn("new build", self.entry(report, directory)["reason"])
        self.assertTrue(directory.exists())

    def test_recreated_path_is_reported_and_not_retried(self):
        directory = self.cache()
        remove = shutil.rmtree

        def recreate(path):
            remove(path)
            path.mkdir()
            (path / "new-output").write_text("new build\n")

        with patch.object(caches.shutil, "rmtree", side_effect=recreate) as mocked:
            report = caches.report("clean", [self.worktree, self.worktree], inactive)
        self.assertEqual(mocked.call_count, 1)
        self.assertEqual(self.entry(report, directory)["status"], "recreated")
        self.assertTrue((directory / "new-output").exists())

    def test_failed_removal_is_not_success(self):
        directory = self.cache()
        with patch.object(caches.shutil, "rmtree", side_effect=PermissionError("fixture permission failure")):
            report = caches.report("clean", [self.worktree], inactive)
        self.assertEqual(self.entry(report, directory)["status"], "failed")
        self.assertEqual(report["counts"]["failed"], 1)
        self.assertEqual(report["counts"]["removed"], 0)
        self.assertTrue(directory.exists())

    def test_unselected_debugger_with_open_cache_file_retains_it(self):
        directory = self.cache()
        real_run = caches.run

        def inventory(args, cwd=None):
            if args[0] == "git":
                return real_run(args, cwd)
            if args == ["ps", "-axo", "pid=,comm="]:
                return result("57 lldb\n")
            if args[0] == "lsof":
                self.assertNotIn("-p", args)
                return result(f"p57\nfcwd\nn/\nf10\nn{directory}/generated.bin\n")
            if args == ["ps", "-p", "57", "-o", "comm="]:
                return result("lldb\n")
            raise AssertionError(f"unexpected inventory command: {args}")

        with patch.object(caches.shutil, "which", return_value="/fixture/tool"), patch.object(caches, "run", side_effect=inventory):
            report = caches.report("clean", [self.worktree])
        self.assertEqual(self.entry(report, directory)["status"], "retained")
        self.assertIn("57 (lldb) has files open", self.entry(report, directory)["reason"])
        self.assertTrue((directory / "generated.bin").exists())


class ActivityTests(unittest.TestCase):
    def probe(self, ps, lsof, alive="swift-frontend\n", package=None):
        pid, command, arguments = ps.strip().split(None, 2)
        responses = iter((result(f"{pid} {command}\n"), result(arguments), result(lsof), result(alive)))
        with patch.object(caches.shutil, "which", return_value="/fixture/tool"), patch.object(caches, "run", side_effect=lambda *_: next(responses)):
            return caches.activity_probe(Path("/repo/linked"), Path("/repo/linked/DerivedData/ModuleCache.noindex"), package)

    def test_build_cwd_owns_worktree_caches(self):
        report = self.probe("42 swift-frontend swift-frontend -c /other/source.swift\n", "p42\nfcwd\nn/repo/linked/Sources\n")
        self.assertFalse(report["safe"])

    def test_sandbox_profile_text_is_not_ownership(self):
        ps = '42 swift-frontend swift-frontend -profile "(allow file-read* (subpath /repo/linked))" /other/source.swift\n'
        self.assertTrue(self.probe(ps, "p42\nfcwd\nn/other\n")["safe"])

    def test_index_open_files_only_retain_affected_cache_or_package(self):
        ps = "42 sourcekit-lsp sourcekit-lsp\n"
        opened = "p42\nfcwd\nn/\nf10\nn/repo/unrelated/DerivedData/ModuleCache.noindex/file\n"
        self.assertTrue(self.probe(ps, opened, "sourcekit-lsp\n")["safe"])
        opened = "p42\nfcwd\nn/\nf10\nn/repo/linked/DerivedData/ModuleCache.noindex/file\n"
        self.assertFalse(self.probe(ps, opened, "sourcekit-lsp\n")["safe"])
        opened = "p42\nfcwd\nn/\nf10\nn/repo/linked/Package/Sources/file.swift\n"
        self.assertFalse(self.probe(ps, opened, "sourcekit-lsp\n", Path("/repo/linked/Package"))["safe"])

    def test_index_cache_argument_retains_cache_before_files_are_open(self):
        ps = "42 sourcekit-lsp sourcekit-lsp -module-cache-path /repo/linked/DerivedData/ModuleCache.noindex\n"
        report = self.probe(ps, "p42\nfcwd\nn/\n", "sourcekit-lsp\n")
        self.assertFalse(report["safe"])
        self.assertIn("open files or arguments", report["reasons"][0])

    def test_index_arguments_only_retain_the_affected_package(self):
        ps = "42 sourcekit-lsp sourcekit-lsp -module-cache-path /repo/linked/Package/.build/arm64-apple-macosx/debug/ModuleCache\n"
        opened = "p42\nfcwd\nn/repo/linked/OtherPackage\n"
        self.assertFalse(self.probe(ps, opened, "sourcekit-lsp\n", Path("/repo/linked/Package"))["safe"])
        self.assertTrue(self.probe(ps, opened, "sourcekit-lsp\n", Path("/repo/linked/OtherPackage"))["safe"])

    def test_disappeared_compiler_is_not_an_active_blocker(self):
        responses = iter((result("42 swift-frontend\n"), result(returncode=1), result("p1\nfcwd\nn/\n"), result(returncode=1)))
        with patch.object(caches.shutil, "which", return_value="/fixture/tool"), patch.object(caches, "run", side_effect=lambda *_: next(responses)):
            self.assertTrue(caches.activity_probe(Path("/repo/linked"), Path("/repo/linked/DerivedData/Build/Products"))["safe"])

    def test_live_process_without_open_file_evidence_is_uncertain(self):
        self.assertFalse(self.probe("42 swift-frontend swift-frontend /other/Source.swift\n", "")["safe"])

    def test_root_cwd_does_not_establish_builder_ownership(self):
        report = self.probe("42 swift-frontend swift-frontend -c Source.swift\n", "p42\nfcwd\nn/\n")
        self.assertFalse(report["safe"])
        self.assertIn("unresolved ownership", report["reasons"][0])

    def test_quoted_parentheses_paths_establish_builder_ownership(self):
        responses = iter((result("42 swift-frontend\n"), result('swift-frontend -c "/repo/linked (feature)/Source.swift"\n'),
                          result("p42\nfcwd\nn/\n"), result("swift-frontend\n")))
        with patch.object(caches.shutil, "which", return_value="/fixture/tool"), patch.object(caches, "run", side_effect=lambda *_: next(responses)):
            report = caches.activity_probe(Path("/repo/linked (feature)"), Path("/repo/linked (feature)/DerivedData/Build/Products"))
        self.assertFalse(report["safe"])
        self.assertIn("belongs to /repo/linked (feature)", report["reasons"][0])

    def test_unavailable_activity_tool_retains(self):
        with patch.object(caches.shutil, "which", return_value=None):
            self.assertFalse(caches.activity_probe(Path("/repo/linked"), Path("/repo/linked/DerivedData/Build/Products"))["safe"])

    def test_failed_all_process_inventory_retains_without_selected_builders(self):
        responses = iter((result("57 lldb\n"), result(returncode=1)))
        with patch.object(caches.shutil, "which", return_value="/fixture/tool"), patch.object(caches, "run", side_effect=lambda *_: next(responses)):
            self.assertFalse(caches.activity_probe(Path("/repo/linked"), Path("/repo/linked/DerivedData/Build/Products"))["safe"])

    def test_command_paths_with_spaces_are_inspected(self):
        command = "/Applications/Xcode Preview.app/usr/bin/swift-frontend"
        responses = iter((result(f"42 {command}\n"), result("swift-frontend /repo/linked/Source.swift\n"),
                          result("p42\nfcwd\nn/other\n"), result(command + "\n")))
        with patch.object(caches.shutil, "which", return_value="/fixture/tool"), patch.object(caches, "run", side_effect=lambda *_: next(responses)):
            self.assertFalse(caches.activity_probe(Path("/repo/linked"), Path("/repo/linked/DerivedData/Build/Products"))["safe"])


if __name__ == "__main__":
    unittest.main()
