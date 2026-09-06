#!/usr/bin/env python3
"""Keep complete, version-consistent package groups after nvfetcher failures."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tomllib

spec = importlib.util.spec_from_file_location("restore", Path(__file__).with_name("restore-sources.py"))
restore = importlib.util.module_from_spec(spec)
spec.loader.exec_module(restore)

# These are naming exceptions, not a list of packages to validate. Everything
# else is discovered from the manifest and flake, so new packages cannot escape CI.
ALIASES = {"codex-code-mode-host": "codex", "zed-preview": "zed-editor-preview"}
STATUS = Path("_sources/update-status.json")


def groups():
    manifest = tomllib.loads(Path("nvfetcher.toml").read_text())
    result = {}
    for key in manifest:
        package = re.sub(r"-(?:aarch64|x86_64)-(?:darwin|linux)$", "", key)
        if package == key:
            raise ValueError(f"source key has no supported platform suffix: {key}")
        result.setdefault(ALIASES.get(package, package), []).append(key)
    return result


def read_current():
    data = json.loads(Path(restore.JSON).read_text())
    _, entries, _ = restore.split_nix(Path(restore.NIX).read_text())
    nix = dict(entries)
    if set(data) != set(nix) or len(entries) != len(nix):
        raise ValueError("generated Nix and JSON source keys disagree")
    # Check the fields these URL-only packages actually consume, too.
    for key, source in data.items():
        block = nix[key]
        for field, value in (("version", source["version"]), ("url", source["src"]["url"]),
                             ("sha256", source["src"]["sha256"])):
            if f'{field} = {json.dumps(value)};' not in block:
                raise ValueError(f"{key}: generated Nix and JSON {field} disagree")
    return data


def problems(data, package_groups):
    bad = {}
    for name, keys in package_groups.items():
        missing = sorted(set(keys) - set(data))
        if missing:
            bad[name] = f"missing sources: {', '.join(missing)}"
        elif len({data[key]["version"] for key in keys}) != 1:
            bad[name] = "platform/companion versions disagree"
    extra = set(data) - {key for keys in package_groups.values() for key in keys}
    if extra:
        raise ValueError(f"sources not declared in manifest: {sorted(extra)}")
    return bad


def restore_packages(names, package_groups):
    # Exact source keys avoid accidentally reverting similarly named packages.
    keys = {key for name in names for key in package_groups[name]}
    restore.restore_json(keys, exact=True)
    restore.restore_nix(keys, exact=True)


def check_reports(directory, package_groups):
    systems = json.loads(subprocess.check_output(
        ["nix", "eval", "--json", ".#packages", "--apply", "builtins.attrNames"], text=True))
    failed = set()
    covered = set()
    for system in systems:
        report = json.loads((Path(directory) / f"{system}.json").read_text())
        expected = json.loads(subprocess.check_output(
            ["nix", "eval", "--json", f".#checks.{system}", "--apply", "builtins.attrNames"], text=True))
        if set(report) != set(expected) or any(type(ok) is not bool for ok in report.values()):
            raise ValueError(f"incomplete or invalid validation report for {system}")
        covered.update(expected)
        failed.update(name for name, ok in report.items() if not ok)
    if covered != set(package_groups):
        raise ValueError("flake checks and manifest package groups disagree")
    return failed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--restore", action="store_true", help="restore incomplete groups from the baseline")
    parser.add_argument("--base", default="HEAD")
    parser.add_argument("--reports", help="restore packages failing any native platform check")
    args = parser.parse_args()
    restore.BASE = args.base
    package_groups = groups()
    data = read_current()
    bad = problems(data, package_groups)
    if args.restore or args.reports:
        # Start a fresh attempt at resolution; preserve its fetch warnings when
        # the separate native-validation stage adds build failures later.
        status = json.loads(STATUS.read_text()) if args.reports and STATUS.exists() else {}
        if args.reports:
            for name in check_reports(args.reports, package_groups):
                bad[name] = "native build or smoke check failed"
        if bad:
            restore_packages(bad, package_groups)
        restored = read_current()
        remaining = problems(restored, package_groups)
        if remaining:
            raise ValueError(f"incomplete source set (repair baseline before publishing): {remaining}")
        if bad:
            for name, reason in sorted(bad.items()):
                version = restored[package_groups[name][0]]["version"]
                status[name] = {"version": version, "reason": reason}
                message = f"Skipped {name} update; keeping version {version}: {reason}"
                print(f"::warning::{message}")
                if summary := os.environ.get("GITHUB_STEP_SUMMARY"):
                    with open(summary, "a") as output:
                        output.write(f"- {message}\n")
        STATUS.write_text(json.dumps(status, indent=2, sort_keys=True) + "\n")
        bad = {}
    if bad:
        raise ValueError(f"incomplete source set (repair baseline before publishing): {bad}")
    print(f"Source guard: {len(package_groups)} complete package groups")


if __name__ == "__main__":
    main()
