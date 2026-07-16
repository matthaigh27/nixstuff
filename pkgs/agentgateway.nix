{ stdenv, lib, sources }:

# agentgateway — https://github.com/agentgateway/agentgateway
#
# One high-performance gateway for service, LLM, and MCP traffic. The official
# native (Rust) release ships raw binaries (not tarballs): linux builds are
# static-pie so no autoPatchelf is needed, darwin is a signed mach-o. Version +
# hash come from nvfetcher.
let
  system = stdenv.hostPlatform.system;
  src = sources."agentgateway-${system}" or (throw "agentgateway: no release binary for ${system}");
in
stdenv.mkDerivation {
  pname = "agentgateway";
  inherit (src) version;

  dontUnpack = true;
  # Native binary: static-pie on Linux, signed mach-o on darwin. Leave it
  # untouched — stripping/patching would break it.
  dontStrip = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 ${src.src} $out/bin/agentgateway
    runHook postInstall
  '';

  meta = {
    description = "High-performance gateway for service, LLM, and MCP traffic (native binary)";
    homepage = "https://github.com/agentgateway/agentgateway";
    license = lib.licenses.asl20;
    mainProgram = "agentgateway";
    platforms = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
