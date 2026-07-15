{ stdenvNoCC, lib, sources }:

# Prebuilt mise release for Apple Silicon (what https://mise.run installs).
#
# Why not the nixpkgs source build? mise's OCI test
# `preserve_metadata_dir_layer_keeps_special_permission_bits` fails in the nix
# build sandbox on darwin (the sandbox strips setuid/sticky bits), so nixpkgs'
# aarch64-darwin CI can't publish a cached binary — every Mac rebuild has to
# recompile mise from source (a slow Rust build with a huge dep tree). mise
# ships a self-contained, codesigned macOS-arm64 release binary, so we vendor
# that: no recompile, no test-skip hack. Linux keeps the nixpkgs build, which is
# cached upstream (the test passes there). Version + hash come from nvfetcher.
let
  source = sources.mise-aarch64-darwin;
in
stdenvNoCC.mkDerivation {
  pname = "mise";
  inherit (source) version src;

  sourceRoot = "mise";

  # Self-contained, codesigned mach-o linking only system libraries — install it
  # verbatim. `dontFixup` avoids stripping/patching, which would break the
  # signature and stop it running on Apple Silicon.
  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -R bin man share $out/
    runHook postInstall
  '';

  dontFixup = true;

  meta = {
    description = "The front-end to your dev env (official Apple Silicon release binary)";
    homepage = "https://mise.jdx.dev";
    license = lib.licenses.mit;
    mainProgram = "mise";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
