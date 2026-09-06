{
  description = "Vendored prebuilt release binaries (auto-updated by nvfetcher + GitHub Actions), consumed as a flake input";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;

      pkgFiles = {
        pi = ./pkgs/pi.nix;
        buzz-desktop = ./pkgs/buzz-desktop.nix;
        cli-proxy-api = ./pkgs/cli-proxy-api.nix;
        claude-code = ./pkgs/claude-code.nix;
        codex = ./pkgs/codex.nix;
        grok = ./pkgs/grok.nix;
        agentgateway = ./pkgs/agentgateway.nix;
        mise = ./pkgs/mise.nix;
        llama-cpp = ./pkgs/llama-cpp.nix;
        zed-editor-preview = ./pkgs/zed-preview.nix;
        vite-plus = ./pkgs/vite-plus.nix;
      };

      # The vendored set built against a given pkgs, gated to the packages that
      # ship an asset for that platform (meta.platforms is the source of truth).
      packagesFor = pkgs:
        let
          sources = pkgs.callPackage ./_sources/generated.nix { };
          all = builtins.mapAttrs (_: p: pkgs.callPackage p { inherit sources; }) pkgFiles;
        in
        nixpkgs.lib.filterAttrs
          (_: p: builtins.elem pkgs.stdenv.hostPlatform.system p.meta.platforms)
          all;

      # Standalone build/CI surface. Uses an allowUnfree pkgs (separate from any
      # consumer) so `nix build .#claude-code` works without --impure, and so the
      # overlay can read the per-system package NAMES from here without forcing
      # anything against the consumer's `final` (which would recurse).
      pkgsBySystem = forAllSystems (system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        });
      packagesBySystem = builtins.mapAttrs (_: packagesFor) pkgsBySystem;
      updateStatus = builtins.fromJSON (builtins.readFile ./_sources/update-status.json);
      # Trace at consumption time so a skipped CI update is visible on the
      # machine doing the rebuild, even when the old derivation is cached.
      # Keep this outside packagesFor's platform filtering: evaluating metadata
      # must not emit warnings for every unused/unsupported package.
      warnedPackagesBySystem = builtins.mapAttrs (_: packages:
        builtins.mapAttrs (name: package:
          let status = updateStatus.${name} or null; in
          if status != null && status.version == package.version then
            builtins.trace
              "warning: nixstuff: ${name} update skipped; keeping version ${status.version}. ${status.reason}."
              package
          else package
        ) packages
      ) packagesBySystem;
    in
    {
      packages = warnedPackagesBySystem;

      # Every exported package gets a native build + installed-entrypoint check.
      # These run after fixup, catching missing dylibs/interpreters and damaged
      # signatures that a successful copy-only derivation would otherwise miss.
      checks = forAllSystems (system:
        let pkgs = pkgsBySystem.${system}; in
        builtins.mapAttrs (name: package:
          pkgs.runCommand "${name}-smoke-${package.version}" { } ''
            export HOME="$TMPDIR/smoke-home"
            mkdir -p "$HOME"
            ${if name == "buzz-desktop" then ''
              # A GUI cannot be launched in a headless Nix build sandbox.
              test -x ${pkgs.lib.getExe package}
              test -f ${package}/Applications/Buzz.app/Contents/Info.plist
            '' else if name == "llama-cpp" then ''
              ${package}/bin/llama-cli --version
              ${package}/bin/llama-server --version
              ${package}/bin/llama-bench --help
            '' else if name == "cli-proxy-api" then ''
              ${pkgs.lib.getExe package} -h
            '' else ''
              ${pkgs.lib.getExe package} --version
            ''}
            touch "$out"
          ''
        ) packagesBySystem.${system});

      # Resolve update tooling through flake.lock as well as package dependencies.
      apps = forAllSystems (system: {
        update-sources = {
          type = "app";
          program = "${pkgsBySystem.${system}.nvfetcher}/bin/nvfetcher";
        };
      });

      # Grafts the vendored packages over nixpkgs by name. These are the same
      # derivations as `packages` (pre-built here against nixpkgs with
      # allowUnfree), so claude-code carries no unfree re-check into the consumer
      # — matching how sadjow's flakes work, and needed because my systems keep
      # nixpkgs.config.allowUnfree = false. nixstuff's nixpkgs `follows` the
      # consumer's, so there's no version skew from the separate instantiation.
      # Only packages with an asset for the build platform are present, so
      # mise/llama-cpp fall back to nixpkgs off aarch64-darwin and
      # zed-editor-preview only appears on x86_64-linux.
      overlays.default = final: prev:
        warnedPackagesBySystem.${prev.stdenv.hostPlatform.system} or { };
    };
}
