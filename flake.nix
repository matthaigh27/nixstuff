{
  description = "Matt's vendored prebuilt release binaries (auto-updated by nvfetcher + GitHub Actions), consumed as a flake input by nixfiles";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;

      # Every vendored package, evaluated for a given system. Each derivation's
      # meta.platforms says where it actually builds; we filter to those below so
      # `packages.<system>` only ever exposes things valid on that system.
      allFor = system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          sources = pkgs.callPackage ./_sources/generated.nix { };
          call = p: pkgs.callPackage p { inherit sources; };
        in
        {
          pi = call ./pkgs/pi.nix;
          cli-proxy-api = call ./pkgs/cli-proxy-api.nix;
          mise = call ./pkgs/mise.nix;
          llama-cpp = call ./pkgs/llama-cpp.nix;
        };
    in
    {
      packages = forAllSystems (system:
        nixpkgs.lib.filterAttrs
          (_: p: builtins.elem system p.meta.platforms)
          (allFor system));

      # Grafts the vendored packages over nixpkgs by name. On a given system it
      # only overrides packages that ship an asset for it — so `mise`/`llama-cpp`
      # fall back to nixpkgs everywhere except aarch64-darwin, and `pi` /
      # `cli-proxy-api` (not in nixpkgs) appear on every supported system.
      overlays.default = final: prev:
        self.packages.${prev.stdenv.hostPlatform.system} or { };
    };
}
