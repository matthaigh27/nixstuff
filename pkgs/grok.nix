{ stdenv, lib, makeBinaryWrapper, git, bubblewrap, sources }:

# Grok Build (`grok`) — https://github.com/xai-org/grok-build
#
# SpaceXAI's terminal coding agent / TUI. The official prebuilt release binary:
# musl + `crt-static` (static-pie) on Linux, so no autoPatchelf is needed, and a
# hardened-runtime, team-signed mach-o on darwin — installed byte-for-byte
# either way, since stripping or patching would break it. Version + hash come
# from nvfetcher, which reads x.ai's plain-text `stable` channel pointer (there
# are no GitHub releases to track).
#
# Upstream's install.sh links the same binary as both `grok` and `agent`; only
# `grok` is installed here, `agent` being far too generic a name for PATH.
#
# Wrapping puts the helpers grok shells out to on PATH: git (worktrees and
# session snapshots) everywhere, plus bubblewrap for `--sandbox` on Linux.
# Unlike claude-code/codex there is no env-var kill switch for the self-updater
# — that lever is `[cli] auto_update` in ~/.grok/config.toml, so a consumer has
# to turn it off there (see home/common/grok.nix in nixfiles).
let
  system = stdenv.hostPlatform.system;
  source = sources."grok-${system}" or (throw "grok: no release binary for ${system}");
in
stdenv.mkDerivation {
  pname = "grok";
  inherit (source) version;

  dontUnpack = true;
  dontStrip = true;
  dontFixup = true;

  nativeBuildInputs = [ makeBinaryWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -m755 ${source.src} $out/bin/.grok-unwrapped

    makeBinaryWrapper $out/bin/.grok-unwrapped $out/bin/grok \
      --prefix PATH : ${
        lib.makeBinPath (
          [ git ] ++ lib.optionals stdenv.hostPlatform.isLinux [ bubblewrap ]
        )
      }

    runHook postInstall
  '';

  meta = {
    description = "Grok Build — SpaceXAI's agentic coding tool in your terminal";
    homepage = "https://x.ai/cli";
    license = lib.licenses.asl20;
    mainProgram = "grok";
    platforms = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
