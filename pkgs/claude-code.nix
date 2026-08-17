{ stdenv, lib, makeBinaryWrapper, musl, procps, ripgrep, bubblewrap, socat, sources
, binName ? "claude"
}:

# Claude Code — https://github.com/anthropics/claude-code
#
# The official native (Bun-compiled) standalone binary from the GitHub release.
# We take the musl build on Linux. It is dynamically linked despite the release
# asset previously being described as static, so invoke it through nixpkgs'
# musl loader rather than relying on a global /lib/ld-musl-*.so.1. Version and
# per-arch hashes come from nvfetcher.
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

    makeBinaryWrapper \
      ${
        if stdenv.hostPlatform.isLinux then
          "${musl}/lib/ld-musl-${stdenv.hostPlatform.linuxArch}.so.1"
        else
          "$out/bin/.claude-unwrapped"
      } \
      $out/bin/${binName} \
      ${lib.optionalString stdenv.hostPlatform.isLinux "--add-flags $out/bin/.claude-unwrapped"} \
      ${lib.optionalString (!stdenv.hostPlatform.isLinux) "--inherit-argv0"} \
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
