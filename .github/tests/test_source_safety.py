"""Regression tests for publishing deleted sources and partial package updates."""
import importlib.util
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("guard", SCRIPTS / "source-guard.py")
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


def source(key, version="1"):
    return {"name": key, "version": version, "src": {
        "url": f"https://example.invalid/{key}-{version}.tar.gz", "sha256": f"hash-{version}"}}


def write_sources(data):
    Path("_sources").mkdir(exist_ok=True)
    Path("_sources/generated.json").write_text(json.dumps(data, indent=4, sort_keys=True) + "\n")
    blocks = []
    for key, value in sorted(data.items()):
        blocks.append(f'  {key} = {{\n    version = "{value["version"]}";\n    src = fetchurl {{\n'
                      f'      url = "{value["src"]["url"]}";\n'
                      f'      sha256 = "{value["src"]["sha256"]}";\n    }};\n  }};\n')
    Path("_sources/generated.nix").write_text("{ fetchurl }:\n{\n" + "".join(blocks) + "}\n")


class SourceSafety(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.cwd = os.getcwd()
        os.chdir(self.temp.name)
        self.keys = ["llama-cpp-aarch64-darwin", "pi-aarch64-darwin", "pi-x86_64-linux",
                     "codex-aarch64-darwin", "codex-code-mode-host-aarch64-darwin"]
        self.baseline = {key: source(key) for key in self.keys}
        self.write_manifest(self.keys)
        write_sources(self.baseline)
        self.git("init", "-q")
        self.git("add", ".")
        self.git("-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                 "-c", "commit.gpgsign=false", "commit", "-qm", "baseline")

    def tearDown(self):
        os.chdir(self.cwd)
        self.temp.cleanup()

    def git(self, *args):
        return subprocess.check_output(["git", *args], stderr=subprocess.STDOUT, text=True)

    def write_manifest(self, keys):
        Path("nvfetcher.toml").write_text("".join(f'[{key}]\nsrc.manual = "1"\n' for key in keys))

    def run_script(self, script, *args, success=True):
        result = subprocess.run([sys.executable, str(SCRIPTS / script), *args],
                                capture_output=True, text=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def current(self):
        return guard.read_current()

    def test_deleted_entry_is_restored_in_both_files(self):
        candidate = self.baseline.copy()
        del candidate[self.keys[0]]
        candidate[self.keys[1]] = source(self.keys[1], "2")
        write_sources(candidate)
        self.run_script("restore-sources.py", "llama-cpp-")
        self.assertEqual(self.current()[self.keys[0]], self.baseline[self.keys[0]])
        self.assertEqual(self.current()[self.keys[1]]["version"], "2")

    def test_entirely_empty_output_can_be_restored(self):
        write_sources({})
        self.run_script("source-guard.py", "--restore")
        self.assertEqual(self.current(), self.baseline)
        self.assertTrue(Path("_sources/generated.nix").read_text().endswith("}\n"))

    def test_failed_new_entry_is_removed(self):
        new_key = "new-aarch64-darwin"
        write_sources({**self.baseline, new_key: source(new_key)})
        self.run_script("restore-sources.py", "new-")
        self.assertEqual(self.current(), self.baseline)

    def test_missing_platform_restores_whole_package_but_keeps_good_bump(self):
        candidate = self.baseline.copy()
        del candidate["pi-x86_64-linux"]
        candidate["pi-aarch64-darwin"] = source("pi-aarch64-darwin", "2")
        candidate[self.keys[0]] = source(self.keys[0], "2")
        write_sources(candidate)
        self.run_script("source-guard.py", "--restore")
        self.assertEqual(self.current()["pi-aarch64-darwin"]["version"], "1")
        self.assertEqual(self.current()["pi-x86_64-linux"]["version"], "1")
        self.assertEqual(self.current()[self.keys[0]]["version"], "2")

    def test_skipped_update_records_warning_for_rebuild(self):
        candidate = self.baseline.copy()
        del candidate["llama-cpp-aarch64-darwin"]
        write_sources(candidate)
        result = self.run_script("source-guard.py", "--restore")
        self.assertIn("::warning::Skipped llama-cpp update; keeping version 1", result.stdout)
        status = json.loads(guard.STATUS.read_text())
        self.assertEqual(status["llama-cpp"]["version"], "1")
        self.assertIn("missing sources", status["llama-cpp"]["reason"])
        self.assertEqual(self.current(), self.baseline)

    def test_successful_retry_clears_previous_warning(self):
        guard.STATUS.write_text('{"llama-cpp": {"version": "1", "reason": "missing asset"}}')
        self.run_script("source-guard.py", "--restore")
        self.assertEqual(json.loads(guard.STATUS.read_text()), {})

    def test_build_failure_keeps_fetch_warning_and_restores_only_failed_package(self):
        fetch_warning = {"version": "1", "reason": "missing asset"}
        guard.STATUS.write_text(json.dumps({"llama-cpp": fetch_warning}))
        candidate = self.baseline.copy()
        for key in ("pi-aarch64-darwin", "pi-x86_64-linux",
                    "codex-aarch64-darwin", "codex-code-mode-host-aarch64-darwin"):
            candidate[key] = source(key, "2")
        write_sources(candidate)
        with patch.object(guard, "check_reports", return_value={"pi"}), \
             patch.object(sys, "argv", ["source-guard.py", "--reports", "reports"]), \
             contextlib.redirect_stdout(io.StringIO()):
            guard.main()
        status = json.loads(guard.STATUS.read_text())
        self.assertEqual(status["llama-cpp"], fetch_warning)
        self.assertEqual(status["pi"]["version"], "1")
        self.assertEqual(self.current()["pi-aarch64-darwin"]["version"], "1")
        self.assertEqual(self.current()["pi-x86_64-linux"]["version"], "1")
        self.assertEqual(self.current()["codex-aarch64-darwin"]["version"], "2")

    def test_mismatched_companion_reverts_cli_and_companion(self):
        write_sources({**self.baseline, "codex-aarch64-darwin": source("codex-aarch64-darwin", "2")})
        self.run_script("source-guard.py", "--restore")
        self.assertEqual(self.current(), self.baseline)

    def test_mismatched_formats_are_rejected(self):
        path = Path("_sources/generated.nix")
        path.write_text(path.read_text().replace('version = "1"', 'version = "2"', 1))
        self.run_script("source-guard.py", success=False)

    def test_unrecoverable_missing_source_blocks_publish(self):
        self.write_manifest([*self.keys, "new-aarch64-darwin"])
        self.run_script("source-guard.py", "--restore", success=False)

    def test_missing_baseline_blocks_restore(self):
        self.run_script("restore-sources.py", "--base", "not-a-commit", "pi-", success=False)
        self.assertEqual(self.current(), self.baseline)

    def test_missing_platform_report_blocks_publish(self):
        with patch.object(guard.subprocess, "check_output", return_value='["aarch64-darwin"]'):
            with self.assertRaises(FileNotFoundError):
                guard.check_reports("reports", guard.groups())

    def test_failed_platform_reverts_whole_package(self):
        Path("reports").mkdir()
        Path("reports/aarch64-darwin.json").write_text(json.dumps({"pi": False, "llama-cpp": True, "codex": True}))
        Path("reports/x86_64-linux.json").write_text(json.dumps({"pi": True}))
        responses = ['["aarch64-darwin", "x86_64-linux"]', '["pi", "llama-cpp", "codex"]', '["pi"]']
        with patch.object(guard.subprocess, "check_output", side_effect=responses):
            self.assertEqual(guard.check_reports("reports", guard.groups()), {"pi"})

    def test_incomplete_package_report_blocks_publish(self):
        Path("reports").mkdir()
        Path("reports/aarch64-darwin.json").write_text('{"pi": true}')
        with patch.object(guard.subprocess, "check_output", side_effect=['["aarch64-darwin"]', '["pi", "llama-cpp"]']):
            with self.assertRaises(ValueError):
                guard.check_reports("reports", guard.groups())


if __name__ == "__main__":
    unittest.main()
