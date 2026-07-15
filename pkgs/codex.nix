{ stdenv, lib, makeWrapper, bubblewrap, sources }:

# OpenAI Codex CLI — https://github.com/openai/codex
#
# The official native (Rust) release binary. Linux uses the static musl build,
# so no autoPatchelf is needed. codex >= 0.143 spawns a sibling
# `codex-code-mode-host` binary (found next to the running executable) when
# "code mode" is on, shipped as its own release asset — so we install it into
# the same bin/ directory. Version + hashes come from nvfetcher.
#
# Wrapping mirrors sadjow/codex-cli-nix: disable the self-updater and, on Linux,
# put bubblewrap on PATH for the sandbox.
let
  system = stdenv.hostPlatform.system;
  platformMap = {
    aarch64-darwin = "aarch64-apple-darwin";
    aarch64-linux = "aarch64-unknown-linux-musl";
    x86_64-linux = "x86_64-unknown-linux-musl";
  };
  platform = platformMap.${system} or (throw "codex: unsupported system ${system}");
  codexSrc = sources."codex-${system}" or (throw "codex: no release binary for ${system}");
  hostSrc = sources."codex-code-mode-host-${system}";
in
stdenv.mkDerivation {
  pname = "codex";
  inherit (codexSrc) version;

  dontUnpack = true;
  # Native binaries: musl-static on Linux, signed mach-o on darwin. Leave them
  # untouched — stripping/patching would break them.
  dontStrip = true;
  dontFixup = true;

  nativeBuildInputs = [ makeWrapper ];

  buildPhase = ''
    runHook preBuild
    mkdir -p build
    tar -xzf ${codexSrc.src} -C build
    mv build/codex-${platform} build/codex
    tar -xzf ${hostSrc.src} -C build
    mv build/codex-code-mode-host-${platform} build/codex-code-mode-host
    chmod u+w,+x build/codex build/codex-code-mode-host
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp build/codex $out/bin/codex-raw
    cp build/codex-code-mode-host $out/bin/codex-code-mode-host
    chmod +x $out/bin/codex-raw $out/bin/codex-code-mode-host

    makeWrapper "$out/bin/codex-raw" "$out/bin/codex" \
      --run 'export CODEX_EXECUTABLE_PATH="$HOME/.local/bin/codex"' \
      --set DISABLE_AUTOUPDATER 1 \
      ${lib.optionalString stdenv.hostPlatform.isLinux
        ''--prefix PATH : "${lib.makeBinPath [ bubblewrap ]}"''}

    runHook postInstall
  '';

  meta = {
    description = "OpenAI Codex CLI — agentic coding tool in your terminal (native binary)";
    homepage = "https://github.com/openai/codex";
    license = lib.licenses.asl20;
    mainProgram = "codex";
    platforms = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
