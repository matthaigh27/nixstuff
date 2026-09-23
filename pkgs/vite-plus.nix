{ stdenv, lib, sources }:

# Vite+ — https://github.com/voidzero-dev/vite-plus
#
# The unified toolchain and entry point for web development, shipped as a single
# native (Rust) `vp` binary inside a tarball. The linux builds are static-pie
# musl and darwin is a signed mach-o, so — like agentgateway/codex — the binary
# is left untouched (no strip/patch/autoPatchelf). Version + hash come from
# nvfetcher.
let
  system = stdenv.hostPlatform.system;
  src = sources."vite-plus-${system}" or (throw "vite-plus: no release asset for ${system}");
in
stdenv.mkDerivation {
  pname = "vite-plus";
  inherit (src) version;

  inherit (src) src;
  sourceRoot = ".";

  # Native binary: static-pie musl on Linux, signed mach-o on darwin. Leave it
  # untouched — stripping/patching would break it.
  dontStrip = true;
  dontFixup = true;

  # Keep the support files beside the binary, matching the release archive.
  # Since Nix has already installed the payload, add upstream's setup-complete
  # marker to prevent the first launch from trying to copy itself into HOME and
  # download dependencies. The binary self-dispatches as vpx from argv[0].
  installPhase = ''
    runHook preInstall
    install -Dm755 vp $out/bin/vp
    install -Dm644 toolchain.json $out/bin/toolchain.json
    install -Dm644 sync-versions/bin.mjs $out/bin/sync-versions/bin.mjs
    touch $out/bin/.vp-setup-complete
    ln -s vp $out/bin/vpx
    runHook postInstall
  '';

  meta = {
    description = "Vite+ — the unified toolchain and entry point for web development (native binary)";
    homepage = "https://github.com/voidzero-dev/vite-plus";
    license = lib.licenses.mit;
    mainProgram = "vp";
    platforms = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
