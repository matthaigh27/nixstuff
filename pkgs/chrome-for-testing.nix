{ stdenvNoCC, lib, unzip, sources }:

# Chrome for Testing — https://github.com/GoogleChromeLabs/chrome-for-testing
#
# Google's official automation build of stable Chrome, tracked via nvfetcher
# from the last-known-good-versions JSON. It ships under its own bundle id
# (com.google.chrome.for.testing), so a headless instance driven by an agent
# never registers as the user's Chrome with LaunchServices. Vendored as-is into
# $out/Applications; $out/bin gets an exec wrapper rather than a symlink, since
# Chrome locates its framework relative to the real executable path.
#
# macOS aarch64 only.
let
  source =
    sources."chrome-for-testing-aarch64-darwin"
      or (throw "chrome-for-testing: no release asset for this platform");
  app = "Google Chrome for Testing.app";
in
stdenvNoCC.mkDerivation {
  pname = "chrome-for-testing";
  inherit (source) version src;

  nativeBuildInputs = [ unzip ];
  sourceRoot = "chrome-mac-arm64";

  # Prebuilt, signed Mach-O bundle — leave it untouched.
  dontStrip = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications" "$out/bin"
    cp -R "${app}" "$out/Applications/"

    cat > "$out/bin/chrome-for-testing" <<SH
    #!/bin/sh
    exec "$out/Applications/${app}/Contents/MacOS/Google Chrome for Testing" "\$@"
    SH
    chmod +x "$out/bin/chrome-for-testing"

    runHook postInstall
  '';

  meta = {
    description = "Chrome for Testing — stable Chrome built for automation, with its own bundle id";
    homepage = "https://github.com/GoogleChromeLabs/chrome-for-testing";
    license = lib.licenses.unfree;
    platforms = [ "aarch64-darwin" ];
    mainProgram = "chrome-for-testing";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
