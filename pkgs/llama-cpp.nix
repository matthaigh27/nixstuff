{ stdenvNoCC, lib, sources }:

# Prebuilt llama.cpp release for Apple Silicon.
#
# Why not the nixpkgs source build? nixpkgs compiles llama.cpp against its own
# (older) Apple SDK, so the Metal-4 *tensor API* shaders fail to compile at
# runtime and llama.cpp disables them (`has tensor = false`) — no access to the
# M5's GPU neural accelerators. The upstream CI build is compiled against
# Xcode's macOS-26 / Metal-4 SDK, so the tensor kernels compile and
# `has tensor = true`. Apple's Metal toolchain isn't redistributable inside the
# nix sandbox, so nixpkgs can't reproduce that build; vendoring the official
# release binary is the reliable way to get tensor acceleration. Linux keeps the
# nixpkgs source build. Version + hash come from nvfetcher.
let
  source = sources.llama-cpp-aarch64-darwin;
in
stdenvNoCC.mkDerivation {
  pname = "llama-cpp";
  inherit (source) version src;

  sourceRoot = "llama-b${source.version}";

  # The release ships executables and their dylibs side by side, linked with an
  # `@loader_path` rpath — so keep them in one directory. Copy them verbatim:
  # patching install-names or stripping would invalidate the ad-hoc code
  # signatures, so `dontFixup` leaves the signed mach-o binaries untouched.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp -R ./* $out/bin/
    runHook postInstall
  '';

  dontFixup = true;

  meta = {
    description = "Inference of Meta's LLaMA model (and others) in pure C/C++ (official Apple Silicon release with Metal-4 tensor API)";
    homepage = "https://github.com/ggml-org/llama.cpp";
    license = lib.licenses.mit;
    mainProgram = "llama-cli";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
