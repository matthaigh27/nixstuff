{
  description = "Matt's vendored prebuilt release binaries (auto-updated by nvfetcher + GitHub Actions), consumed as a flake input by nixfiles";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;

      pkgFiles = {
        pi = ./pkgs/pi.nix;
        cli-proxy-api = ./pkgs/cli-proxy-api.nix;
        claude-code = ./pkgs/claude-code.nix;
        codex = ./pkgs/codex.nix;
        mise = ./pkgs/mise.nix;
        llama-cpp = ./pkgs/llama-cpp.nix;
        zed-editor-preview = ./pkgs/zed-preview.nix;
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
      packagesBySystem = forAllSystems (system:
        packagesFor (import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        }));
    in
    {
      packages = packagesBySystem;

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
        packagesBySystem.${prev.stdenv.hostPlatform.system} or { };
    };
}
