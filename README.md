# nixstuff

Vendored prebuilt release binaries that aren't in nixpkgs (or that I want
straight from upstream), packaged as a flake and consumed as an input by my
[nixfiles](https://github.com/matthaigh27/nixfiles).

## Why this exists

`nix flake update` only re-locks flake *inputs*. Packages vendored locally
inside nixfiles (a hardcoded `version` + hash in a `.nix` file) are invisible to
it, so they never moved forward on update. Putting them in their own flake here —
kept current by CI — means nixfiles pulls the bumps forward with a plain
`nix flake update`, exactly like any other input.

## How it updates

- [`nvfetcher.toml`](./nvfetcher.toml) lists one entry per (package, platform),
  tracking each project's latest GitHub release.
- `nvfetcher` re-resolves every entry and writes versions + per-arch hashes to
  [`_sources/generated.nix`](./_sources/generated.nix). It fetches by URL, so a
  single run refreshes all platforms regardless of the machine it runs on.
- [`.github/workflows/update.yml`](./.github/workflows/update.yml) runs
  `nvfetcher` daily (and on demand), builds the Linux packages to catch bad
  bumps, and commits the result.

To update by hand: `nix run nixpkgs#nvfetcher` then commit.

## Packages

| package         | platforms                                   | notes |
|-----------------|---------------------------------------------|-------|
| `pi`            | darwin arm64/x64, linux arm64/x64           | pi.dev standalone Bun binary; autoPatchelf on Linux |
| `cli-proxy-api` | darwin arm64, linux amd64/arm64             | CLIProxyAPI; autoPatchelf on Linux |
| `mise`          | darwin arm64                                 | Linux uses nixpkgs |
| `llama-cpp`     | darwin arm64                                 | Metal-4 tensor build; Linux uses nixpkgs |

`packages.<system>` only exposes the packages with an asset for that system.
`overlays.default` grafts them over nixpkgs by name (falling back to nixpkgs
where there's no vendored asset).
