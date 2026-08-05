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
import sys

NIX = "_sources/generated.nix"
JSON = "_sources/generated.json"


def head(path):
    r = subprocess.run(["git", "show", f"HEAD:{path}"], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def matches(key, prefixes):
    return any(key.startswith(p) for p in prefixes)


def restore_json(prefixes):
    cur = json.load(open(JSON))
    old_text = head(JSON)
    old = json.loads(old_text) if old_text else {}
    for key in [k for k in cur if matches(k, prefixes)]:
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
    while i < len(lines) and not ENTRY.match(lines[i]):
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
        block.append(lines[i])  # the `  };` line
        i += 1
        entries.append((m.group(1), "".join(block)))
    return "".join(header), entries, "".join(footer)


def restore_nix(prefixes):
    _, old_entries, _ = split_nix(head(NIX) or "")
    old = dict(old_entries)
    header, entries, footer = split_nix(open(NIX).read())
    out = []
    for key, block in entries:
        if matches(key, prefixes):
            if key in old:
                out.append((key, old[key]))  # revert to committed block
            # else: drop the entry entirely
        else:
            out.append((key, block))
    with open(NIX, "w") as f:
        f.write(header)
        for _, block in out:
            f.write(block)
        f.write(footer)


def main():
    prefixes = sys.argv[1:]
    if not prefixes:
        sys.exit("usage: restore-sources.py <prefix> [<prefix> ...]")
    restore_json(prefixes)
    restore_nix(prefixes)


if __name__ == "__main__":
    main()
