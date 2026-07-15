{
  description = "Matt's vendored prebuilt release binaries (auto-updated by nvfetcher + GitHub Actions), consumed as a flake input by nixfiles";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;

      # The vendored package set, built against a given pkgs instance and gated
      # to the packages that actually ship an asset for that platform (each
      # derivation's meta.platforms is the source of truth). Taking `pkgs` as an
      # argument is what lets the overlay build against the *consumer's* pkgs —
      # so their nixpkgs config (allowUnfree, etc.) and overlays apply, and no
      # second nixpkgs is instantiated.
      packagesFor = pkgs:
        let
          sources = pkgs.callPackage ./_sources/generated.nix { };
          call = p: pkgs.callPackage p { inherit sources; };
          all = {
            pi = call ./pkgs/pi.nix;
            cli-proxy-api = call ./pkgs/cli-proxy-api.nix;
            claude-code = call ./pkgs/claude-code.nix;
            codex = call ./pkgs/codex.nix;
            mise = call ./pkgs/mise.nix;
            llama-cpp = call ./pkgs/llama-cpp.nix;
            zed-editor-preview = call ./pkgs/zed-preview.nix;
          };
        in
        nixpkgs.lib.filterAttrs
          (_: p: builtins.elem pkgs.stdenv.hostPlatform.system p.meta.platforms)
          all;
    in
    {
      # Standalone build/CI surface. Uses an allowUnfree pkgs so `nix build
      # .#claude-code` works without --impure (this is my repo; I allow it).
      packages = forAllSystems (system:
        packagesFor (import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        }));

      # Grafts the vendored packages over nixpkgs by name, built against the
      # consumer's pkgs. Only overrides packages that ship an asset for the build
      # platform — so mise/llama-cpp fall back to nixpkgs off aarch64-darwin,
      # zed-editor-preview only appears on x86_64-linux, and pi/cli-proxy-api/
      # claude-code/codex appear on every supported system.
      overlays.default = final: prev: packagesFor final;
    };
}
