#!/usr/bin/env python3
"""Drop the bumps for packages that failed to build.

Given one or more nvfetcher source-key prefixes (e.g. `codex-`, `vite-plus-`),
restore every matching entry in _sources/generated.{nix,json} to its committed
(HEAD) state — or remove it entirely if HEAD has no such entry (a brand-new
package that failed its very first build). Every other bump is left untouched,
so a single unbuildable package no longer blocks the rest from being committed.

Usage: restore-sources.py <prefix> [<prefix> ...]
"""
import json
import re
import subprocess

NIX = "_sources/generated.nix"
JSON = "_sources/generated.json"


BASE = "HEAD"


def head(path):
    # A missing baseline is an error, never permission to delete source entries.
    return subprocess.check_output(["git", "show", f"{BASE}:{path}"], text=True)


def matches(key, prefixes, exact=False):
    return key in prefixes if exact else any(key.startswith(p) for p in prefixes)


def restore_json(prefixes, *, exact=False):
    with open(JSON) as f:
        cur = json.load(f)
    old = json.loads(head(JSON))
    for key in [k for k in cur.keys() | old.keys() if matches(k, prefixes, exact)]:
        if key in old:
            cur[key] = old[key]
        else:
            del cur[key]
    with open(JSON, "w") as f:  # match nvfetcher's formatting (4-space, sorted)
        json.dump(cur, f, indent=4, sort_keys=True)
        f.write("\n")


# A top-level entry is `  <name> = {` ... up to the matching `  };`.
ENTRY = re.compile(r"^  (\S+) = \{$")


def split_nix(text):
    """Return (header, [(key, block)], footer)."""
    lines = text.splitlines(keepends=True)
    entries, header, footer, i = [], [], [], 0
    while i < len(lines) and not ENTRY.match(lines[i]) and lines[i].strip() != "}":
        header.append(lines[i])
        i += 1
    while i < len(lines):
        m = ENTRY.match(lines[i])
        if not m:  # trailing `}` and anything after the last entry
            footer = lines[i:]
            break
        block = [lines[i]]
        i += 1
        while i < len(lines) and lines[i] != "  };\n":
            block.append(lines[i])
            i += 1
        if i == len(lines):
            raise ValueError(f"unterminated source entry: {m.group(1)}")
        block.append(lines[i])  # the `  };` line
        i += 1
        entries.append((m.group(1), "".join(block)))
    return "".join(header), entries, "".join(footer)


def restore_nix(prefixes, *, exact=False):
    _, old_entries, _ = split_nix(head(NIX))
    old = dict(old_entries)
    with open(NIX) as f:
        header, entries, footer = split_nix(f.read())
    cur = dict(entries)
    out = []
    for key in sorted(cur.keys() | old.keys()):
        if matches(key, prefixes, exact):
            if key in old:
                out.append((key, old[key]))  # revert to committed block
            # else: drop the entry entirely
        elif key in cur:
            out.append((key, cur[key]))
    with open(NIX, "w") as f:
        f.write(header)
        for _, block in out:
            f.write(block)
        f.write(footer)


def main():
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="HEAD")
    parser.add_argument("prefixes", nargs="+")
    args = parser.parse_args()
    global BASE
    BASE = args.base
    prefixes = args.prefixes
    restore_json(prefixes)
    restore_nix(prefixes)


if __name__ == "__main__":
    main()
