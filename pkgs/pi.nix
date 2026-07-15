{ stdenv, lib, autoPatchelfHook, sources }:

# Pi, the coding agent from https://pi.dev/ (earendil-works/pi).
#
# We vendor the official standalone release — the `bun build --compile`
# executable from the GitHub releases, which embeds the Bun runtime and all deps
# in one self-contained program — for every platform. Version + per-arch hashes
# come from nvfetcher (see nvfetcher.toml / _sources/generated.nix).
#
# The tarball is a `pi/` tree: the `pi` executable plus assets it loads at
# runtime relative to its real path (photon wasm, native clipboard addon,
# themes, ...). So we install the whole tree under libexec and symlink the
# binary onto PATH — the executable resolves through the symlink and still finds
# its siblings.
#
# darwin: the mach-o is codesigned, so `dontFixup` leaves it (and its assets)
# untouched — stripping/patching would break the signature and stop it running.
# Linux: the binary is a dynamically linked ELF, so autoPatchelfHook rewrites
# the interpreter/rpath onto the nix glibc (same treatment as cli-proxy-api).
let
  system = stdenv.hostPlatform.system;
  source =
    sources."pi-${system}"
      or (throw "pi: no release binary for ${system}");
in
stdenv.mkDerivation {
  pname = "pi";
  inherit (source) version src;

  sourceRoot = "pi";

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec/pi $out/bin
    cp -R ./* $out/libexec/pi/
    ln -s $out/libexec/pi/pi $out/bin/pi
    runHook postInstall
  '';

  # darwin only: codesigned mach-o that must not be patched/stripped. On Linux
  # we DO want fixup so autoPatchelfHook runs.
  dontFixup = stdenv.hostPlatform.isDarwin;

  meta = {
    description = "Minimal, customizable AI coding agent (pi.dev, official standalone Bun binary)";
    homepage = "https://pi.dev/";
    license = lib.licenses.mit;
    mainProgram = "pi";
    platforms = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
