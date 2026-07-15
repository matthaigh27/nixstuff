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

      # Grafts the vendored packages over nixpkgs by name, BUILT against the
      # consumer's pkgs (so their config — allowUnfree etc. — and overlays apply,
      # and no second nixpkgs is instantiated). The key set comes from
      # packagesBySystem (static, computed against a separate pkgs), so it never
      # forces a derivation against `final` — doing so would recurse, because
      # callPackage's intersectAttrs forces `final`'s attribute names.
      overlays.default = final: prev:
        let
          # Key off `prev` (already resolved): keying off `final.stdenv` here
          # would force our own key set to compute `final.stdenv`, which recurses.
          # Values are still built with `final` so consumer overlays/config apply.
          system = prev.stdenv.hostPlatform.system;
          sources = final.callPackage ./_sources/generated.nix { };
          names = builtins.attrNames (packagesBySystem.${system} or { });
        in
        nixpkgs.lib.genAttrs names
          (name: final.callPackage pkgFiles.${name} { inherit sources; });
    };
}
