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

  # Vite+ ships a SINGLE binary that self-dispatches on argv[0]: the same `vp`,
  # invoked under the name `vpx`, becomes the package runner (`vpx <pkg> ...`).
  # There is no `vp x` subcommand. Upstream exposes `vpx` at runtime via `vp`'s
  # shim dir on PATH; a static symlink to the same binary is the declarative
  # equivalent and runs the identical (official, unmodified) code path.
  installPhase = ''
    runHook preInstall
    install -Dm755 vp $out/bin/vp
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
