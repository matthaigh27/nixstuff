{ stdenv, lib, patchelf, sources }:

# T3 Code (`t3`) — https://github.com/pingdotgg/t3code (homepage https://t3.codes).
#
# We vendor the official prebuilt Linux release tarball from the GitHub releases
# for each arch; version + per-arch hashes come from nvfetcher (see
# nvfetcher.toml / _sources/generated.nix). The published `t3` npm package is
# only a launcher shim that execs this same build, so packaging the release
# archive directly gives us the real CLI without any npm/node-pty dance.
#
# Linux only: workbox runs `t3 serve` headless (see nixfiles home/workbox). The
# darwin build isn't packaged here yet.
#
# The archive is a single `t3-<ver>-<arch>/` tree (stdenv auto-detects it as the
# sourceRoot): the `t3` executable plus assets it loads relative to its real
# path — client/ web UI, a resource-monitor helper binary, and a node_modules/
# with native glibc addons (node-pty, ffi-rs, msgpackr, libfff_c).
#
# IMPORTANT — why NOT autoPatchelfHook: `t3` is a Node SEA (Single Executable
# Application), a node binary with a blob injected by postject (visible as the
# `.note.node.sea` section). autoPatchelfHook — and stdenv's default
# patchelf/shrink-rpath fixup — relayout the ELF and corrupt that blob, so the
# binary SIGILLs the instant `serve` runs embedded code. Trivial invocations
# (`--version`) exit before touching the blob, which masks the breakage. So we
# disable the automatic ELF fixups and instead set ONLY the interpreter and an
# rpath by hand: patchelf can do that without disturbing the blob. That rpath
# (glibc + libstdc++) also satisfies the dlopened native addons, whose deps are
# the same libs the node runtime already pulls in — verified by booting
# `t3 serve` to "Listening …/ready" on NixOS.
let
  system = stdenv.hostPlatform.system;
  source =
    sources."t3-${system}"
      or (throw "t3: no release binary for ${system}");
  rpath = lib.makeLibraryPath [ stdenv.cc.cc.lib stdenv.cc.libc ];
in
stdenv.mkDerivation {
  pname = "t3";
  inherit (source) version src;

  nativeBuildInputs = [ patchelf ];

  # Node SEA: keep stdenv's fixup away from the binary (patchelf-shrink + strip
  # both corrupt the injected blob). We patch the interpreter/rpath ourselves.
  dontPatchELF = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec/t3 $out/bin
    cp -R ./* $out/libexec/t3/

    patchelf \
      --set-interpreter "$(cat ${stdenv.cc}/nix-support/dynamic-linker)" \
      --set-rpath "${rpath}" \
      $out/libexec/t3/t3

    # Symlink onto PATH: the SEA resolves client/, node_modules/ and the
    # resource-monitor helper relative to its real path, so it works through the
    # symlink (execPath follows it) — same layout as pi.
    ln -s $out/libexec/t3/t3 $out/bin/t3

    runHook postInstall
  '';

  meta = {
    description = "T3 Code — coding agent CLI (t3.codes), official prebuilt Linux binary";
    homepage = "https://t3.codes";
    license = lib.licenses.mit;
    mainProgram = "t3";
    platforms = [ "aarch64-linux" "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
