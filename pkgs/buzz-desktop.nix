{ stdenvNoCC, lib, undmg, sources }:

# Buzz desktop — https://github.com/block/buzz
#
# The official macOS release .dmg (Tauri 2 app), tracked via nvfetcher. The dmg
# holds a single `Buzz.app` alongside the usual drag-to-`/Applications` symlink;
# we extract with undmg and vendor the bundle into $out/Applications. The bundle
# ships several binaries in Contents/MacOS (buzz, buzz-acp, buzz-agent, …); the
# app's CFBundleExecutable is `buzz-desktop`, which we expose on $out/bin.
#
# macOS aarch64 only for now — the Linux .AppImage/.deb assets aren't packaged.
let
  source =
    sources."buzz-desktop-aarch64-darwin"
      or (throw "buzz-desktop: no release asset for this platform");
in
stdenvNoCC.mkDerivation {
  pname = "buzz-desktop";
  inherit (source) version src;

  sourceRoot = ".";
  nativeBuildInputs = [ undmg ];
  unpackPhase = "undmg $src";

  # Prebuilt, signed Mach-O bundle — leave it untouched.
  dontStrip = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications"
    cp -r "Buzz.app" "$out/Applications/"

    mkdir -p "$out/bin"
    ln -s "$out/Applications/Buzz.app/Contents/MacOS/buzz-desktop" "$out/bin/buzz-desktop"

    runHook postInstall
  '';

  meta = {
    description = "Buzz desktop — a workspace where humans and agents build together, on a relay you own";
    homepage = "https://github.com/block/buzz";
    license = lib.licenses.asl20;
    platforms = [ "aarch64-darwin" ];
    mainProgram = "buzz-desktop";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
