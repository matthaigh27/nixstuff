{
  lib,
  stdenv,
  autoPatchelfHook,
  makeWrapper,
  alsa-lib,
  fontconfig,
  vulkan-loader,
  wayland,
  libxkbcommon,
  openssl,
  xkeyboard_config,
  sources,
}:

# Zed editor, preview channel — the official Linux x86_64 release tarball,
# tracked via nvfetcher (see nvfetcher.toml; the version is read from the
# zed.dev "latest preview" redirect). Dynamically linked, so autoPatchelfHook
# resolves it against nixpkgs libs and a wrapper points it at the GPU/wayland
# runtime bits.
let
  source = sources.zed-preview-x86_64-linux;
in
stdenv.mkDerivation {
  pname = "zed-editor-preview";
  inherit (source) version src;

  nativeBuildInputs = [ autoPatchelfHook makeWrapper ];

  buildInputs = [
    alsa-lib
    fontconfig
    openssl
    wayland
    libxkbcommon
    vulkan-loader
    stdenv.cc.cc.lib
  ];

  # bundled libs are needed for autoPatchelf to resolve against
  appendRunpaths = [ "$out/lib" ];

  installPhase = ''
    mkdir -p $out/bin $out/lib $out/libexec $out/share

    cp -r lib/* $out/lib/
    cp libexec/zed-editor $out/libexec/zed-editor
    cp -r share/* $out/share/

    makeWrapper $out/libexec/zed-editor $out/bin/zeditor-preview \
      --set LD_LIBRARY_PATH "${lib.makeLibraryPath [ vulkan-loader wayland ]}" \
      --set XKB_CONFIG_ROOT "${xkeyboard_config}/share/X11/xkb"
  '';

  meta = {
    description = "Zed preview — high-performance multiplayer code editor";
    homepage = "https://zed.dev";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "zeditor-preview";
  };
}
