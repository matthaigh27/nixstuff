# nixstuff

Vendored prebuilt release binaries that aren't in nixpkgs (or that I want
straight from upstream), packaged as a flake and consumed as an input by my
Nix config.

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
- [`.github/workflows/update.yml`](./.github/workflows/update.yml) runs twice
  daily and on demand. Update tooling comes from this flake's locked nixpkgs.
- Failed fetches can make `nvfetcher --keep-going` **delete** source entries.
  [The source guard](./.github/source-guard.py) restores incomplete package
  groups from the committed baseline before validation. All architectures and
  companions (such as Codex's code-mode-host) must have the same version.
- Native runners build and check **every exported package** on Apple Silicon
  macOS, ARM64 Linux, and x86_64 Linux. `checks.<system>.<package>` runs installed
  CLIs with `--version` or help, catching loader and entrypoint failures after
  packaging. Buzz gets bundle/entrypoint checks because it requires a GUI.
- If any platform fails, that package's entire update is restored to its
  previous pin; passing packages still advance. Missing validation reports or
  incomplete final sources block publication. Retained packages appear in the
  Actions summary and are recorded in `_sources/update-status.json` alongside
  the generated sources. When your local rebuild evaluates an affected package
  through the overlay or `packages`, Nix prints a warning with the retained
  version and reason. The package stays usable, and the warning clears after a
  successful retry. Warnings don't change derivations or force reinstalls.
- [Regular CI](./.github/workflows/check.yml) also runs these checks on pushes
  and pull requests, covering packaging changes as well as automated updates.

To update by hand (Python 3.11+):

```sh
python3 .github/source-guard.py
nix run .#update-sources -- --keep-going
python3 .github/source-guard.py --restore
nix flake check
```

`nix flake check` builds checks for the current system. CI validates the other
systems before automatic updates are committed. To evaluate all platforms
without building, use `nix flake check --all-systems --no-build`.

These are packaging/startup checks, not full application tests. In particular,
Metal tensor acceleration and model inference still need validation on the
target Mac; hosted runners don't guarantee the same GPU as your machine.

To recover a source already deleted from the committed baseline, restore it
from a known working revision, then run the guard and relevant flake checks:

```sh
python3 .github/restore-sources.py --base <good-revision> llama-cpp-
python3 .github/source-guard.py
nix build .#checks.aarch64-darwin.llama-cpp
```

## Packages

| package              | platforms                           | notes |
|----------------------|-------------------------------------|-------|
| `pi`                 | darwin arm64, linux arm64/x64       | pi.dev standalone Bun binary; autoPatchelf on Linux |
| `cli-proxy-api`      | darwin arm64, linux amd64/arm64     | CLIProxyAPI; autoPatchelf on Linux |
| `claude-code`        | darwin arm64, linux arm64/x64       | official native binary; static musl on Linux |
| `codex`              | darwin arm64, linux arm64/x64       | OpenAI Codex native binary + code-mode-host companion |
| `grok`               | darwin arm64, linux arm64/x64       | xAI Grok Build; no GitHub releases — version from x.ai's channel pointer |
| `agentgateway`       | darwin arm64, linux arm64/x64       | service/LLM/MCP gateway; native binary, static-pie on Linux |
| `mise`               | darwin arm64                        | Linux uses nixpkgs |
| `llama-cpp`          | darwin arm64                        | Metal-4 tensor build; Linux uses nixpkgs |
| `zed-editor-preview` | linux x86_64                        | Zed preview channel; version from the zed.dev redirect |
| `vite-plus`          | darwin arm64, linux arm64/x64       | Vite+ unified web toolchain (`vp`); native binary, static-pie musl on Linux |

`packages.<system>` only exposes the packages with an asset for that system.
`overlays.default` grafts them over nixpkgs by name (falling back to nixpkgs
where there's no vendored asset).
