"""Verify warnings reach the consuming Nix process without changing packages."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which("nix"), "requires Nix for evaluation")
class RebuildWarnings(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        for name in ("flake.nix", "flake.lock"):
            shutil.copy2(ROOT / name, self.root / name)
        for name in ("pkgs", "_sources"):
            shutil.copytree(ROOT / name, self.root / name)
        self.version = json.loads((self.root / "_sources/generated.json").read_text())["llama-cpp-aarch64-darwin"]["version"]
        self.status = self.root / "_sources/update-status.json"
        self.status.write_text(json.dumps({"llama-cpp": {"version": self.version, "reason": "release asset unavailable"}}))

    def tearDown(self):
        self.temp.cleanup()

    def evaluate(self, expression):
        result = subprocess.run(
            ["nix", "eval", "--impure", "--raw", "--expr",
             f'let flake = builtins.getFlake "path:{self.root}"; in {expression}'],
            capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def test_overlay_warns_locally_and_retains_the_same_derivation(self):
        expression = '(flake.overlays.default {} { stdenv.hostPlatform.system = "aarch64-darwin"; }).llama-cpp.drvPath'
        warned = self.evaluate(expression)
        self.assertIn(f"warning: nixstuff: llama-cpp update skipped; keeping version {self.version}", warned.stderr)
        self.status.write_text("{}\n")
        clean = self.evaluate(expression)
        self.assertNotIn("update skipped", clean.stderr)
        self.assertEqual(warned.stdout, clean.stdout)

    def test_direct_package_warns_and_still_evaluates(self):
        result = self.evaluate("flake.packages.aarch64-darwin.llama-cpp.version")
        self.assertEqual(result.stdout, self.version)
        self.assertIn("release asset unavailable", result.stderr)

    def test_unused_package_does_not_warn(self):
        result = self.evaluate("flake.packages.aarch64-darwin.mise.version")
        self.assertNotIn("update skipped", result.stderr)

    def test_stale_version_warning_does_not_warn(self):
        self.status.write_text(json.dumps({"llama-cpp": {"version": "old-version", "reason": "missing asset"}}))
        result = self.evaluate("flake.packages.aarch64-darwin.llama-cpp.version")
        self.assertEqual(result.stdout, self.version)
        self.assertNotIn("update skipped", result.stderr)


if __name__ == "__main__":
    unittest.main()
