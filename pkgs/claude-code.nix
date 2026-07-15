{ stdenv, lib, makeBinaryWrapper, procps, ripgrep, bubblewrap, socat, sources
, binName ? "claude"
}:

# Claude Code — https://github.com/anthropics/claude-code
#
# The official native (Bun-compiled) standalone binary from the GitHub release.
# We take the static musl build on Linux, so — unlike a glibc binary — it needs
# no autoPatchelf and runs as-is. Version + per-arch hashes come from nvfetcher.
#
# Wrapping mirrors sadjow/claude-code-nix: disable the self-updater and install
# checks (the store is read-only), force the vendored ripgrep off in favour of a
# nixpkgs one, and put the runtime helpers claude shells out to on PATH
# (bubblewrap/socat power the Linux sandbox).
let
  system = stdenv.hostPlatform.system;
  source =
    sources."claude-code-${system}"
      or (throw "claude-code: no release binary for ${system}");
in
stdenv.mkDerivation {
  pname = "claude-code";
  inherit (source) version src;

  sourceRoot = ".";

  nativeBuildInputs = [ makeBinaryWrapper ];

  # Bun trailer: stripping/patching corrupts the embedded payload. The musl
  # build is static, so there is nothing to autoPatchelf anyway.
  dontStrip = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin

    install -m755 claude $out/bin/.claude-unwrapped

    makeBinaryWrapper $out/bin/.claude-unwrapped $out/bin/${binName} \
      --inherit-argv0 \
      --set DISABLE_AUTOUPDATER 1 \
      --set DISABLE_INSTALLATION_CHECKS 1 \
      --set USE_BUILTIN_RIPGREP 0 \
      --prefix PATH : ${
        lib.makeBinPath (
          [ procps ripgrep ]
          ++ lib.optionals stdenv.hostPlatform.isLinux [ bubblewrap socat ]
        )
      }

    runHook postInstall
  '';

  meta = {
    description = "Claude Code — Anthropic's agentic coding tool in your terminal";
    homepage = "https://www.anthropic.com/claude-code";
    license = lib.licenses.unfree;
    mainProgram = binName;
    platforms = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
