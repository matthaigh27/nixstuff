{ stdenv, lib, autoPatchelfHook, sources }:

# CLIProxyAPI (https://github.com/router-for-me/CLIProxyAPI) — a local proxy
# that exposes OpenAI/Gemini/Claude/Codex/Grok-compatible endpoints backed by
# your CLI-tool subscriptions. Not in nixpkgs, and it releases extremely often
# (hundreds of tagged builds), so we vendor the official prebuilt release
# binary and track it directly rather than maintaining a buildGoModule
# vendorHash. Version + per-arch hashes come from nvfetcher (see nvfetcher.toml
# / _sources/generated.nix); `nix flake update` in the consuming flake pulls
# the auto-committed bumps forward.
#
# Each release tarball is a flat tree: the `cli-proxy-api` binary plus LICENSE,
# READMEs and config.example.yaml. On darwin the binary is an adhoc/linker-
# signed mach-o (so `dontFixup` — stripping/patching would break the signature);
# on Linux it's a dynamically linked Go+cgo ELF, so autoPatchelfHook rewrites
# the interpreter/rpath onto the nix glibc.
let
  system = stdenv.hostPlatform.system;
  source =
    sources."cli-proxy-api-${system}"
      or (throw "cli-proxy-api: no release binary for ${system}");
in
stdenv.mkDerivation {
  pname = "cli-proxy-api";
  inherit (source) version src;

  # Tarball has no top-level directory; unpack straight into the build root.
  sourceRoot = ".";

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    install -Dm755 cli-proxy-api $out/bin/cli-proxy-api
    install -Dm644 config.example.yaml $out/share/cli-proxy-api/config.example.yaml
    runHook postInstall
  '';

  # darwin: adhoc-signed mach-o — stripping/patching invalidates the signature.
  dontFixup = stdenv.hostPlatform.isDarwin;

  meta = {
    description = "Local proxy exposing OpenAI/Gemini/Claude/Codex/Grok-compatible APIs backed by CLI-tool subscriptions";
    homepage = "https://github.com/router-for-me/CLIProxyAPI";
    license = lib.licenses.mit;
    mainProgram = "cli-proxy-api";
    platforms = [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
