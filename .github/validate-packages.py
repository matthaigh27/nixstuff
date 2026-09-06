#!/usr/bin/env python3
"""Build every flake check on a native runner; record per-package results."""
import argparse
import json
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("system")
    parser.add_argument("--report", required=True)
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()
    native = subprocess.check_output(
        ["nix", "eval", "--impure", "--raw", "--expr", "builtins.currentSystem"], text=True)
    if native != args.system:
        raise ValueError(f"expected a native {args.system} runner, got {native}")
    names = json.loads(subprocess.check_output(
        ["nix", "eval", "--json", f".#checks.{args.system}", "--apply", "builtins.attrNames"], text=True))
    if not names:
        raise ValueError("no checks discovered")
    results = {}
    for name in names:
        print(f"::group::{args.system}: {name}", flush=True)
        try:
            result = subprocess.run(
                ["nix", "build", "--no-link", "-L", f".#checks.{args.system}.{name}"], timeout=900)
            results[name] = result.returncode == 0
        except subprocess.TimeoutExpired:
            results[name] = False
            print(f"::warning::{name}: check exceeded 15 minutes")
        print("::endgroup::", flush=True)
    report = Path(args.report)
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(results, indent=2) + "\n")
    if args.strict and not all(results.values()):
        sys.exit(1)


if __name__ == "__main__":
    main()
