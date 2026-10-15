{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  python312,
  libpulseaudio,
  libxcb,
  libxkbcommon,
  libX11,
  libXext,
  libICE,
  libSM,
  libva,
  libdrm,
  libgbm,
  libglvnd,
  vulkan-loader,
  wayland,
  pixman,
  zlib,
  xrandr,
  xset,
  xauth,
  xorg-server,
  pulseaudio,
  procps,
}:

let
  runtimeLibraries = [
    libpulseaudio
    libxcb
    libxkbcommon
    libX11
    libXext
    libICE
    libSM
    libva
    libdrm
    libgbm
    libglvnd
    vulkan-loader
    wayland
    pixman
  ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "selkies";
  version = "2.0.0";

  # Upstream bundles the matching web client, pixelflux/pcmflux encoders, and
  # Python dependencies in its native release. Relocate that private environment
  # onto Nix's Python with the same ABI, without an FHS container or host libraries.
  src = fetchurl {
    url = "https://github.com/selkies-project/selkies/releases/download/${finalAttrs.version}/selkies-${finalAttrs.version}-ubuntu24.04-amd64.deb";
    hash = "sha256-u6pNcQErk3SnU7ff3cHaB+MfNLBCd/5Ps9BF8Y/Yg5E=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = runtimeLibraries ++ [
    stdenv.cc.cc.lib
    zlib
  ];
  dontBuild = true;
  dontStrip = true;

  unpackPhase = ''
    runHook preUnpack
    ar x "$src"
    tar -xzf data.tar.gz
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib" "$out/libexec" "$out/bin"
    cp -r opt/selkies/lib/python3.12 "$out/lib/"
    cp usr/lib/x86_64-linux-gnu/selkies_*_interposer.so "$out/lib/"

    # Existing sandbox-desktop bookmarks used noVNC's /vnc.html entry point.
    cat > "$out/lib/python3.12/site-packages/selkies/selkies_web/vnc.html" <<'HTML'
    <!doctype html>
    <meta http-equiv="refresh" content="0;url=/">
    <title>Sandbox desktop</title>
    <a href="/">Open desktop</a>
    HTML

    for command in selkies selkies-resize selkies-gpu-probe selkies-session; do
      cp "opt/selkies/bin/$command" "$out/libexec/$command"
      substituteInPlace "$out/libexec/$command" \
        --replace-fail '#!/opt/selkies/bin/python3' '#!${python312.interpreter}'
      makeWrapper "$out/libexec/$command" "$out/bin/$command" \
        --set PYTHONPATH "$out/lib/python3.12/site-packages" \
        --set PYTHONNOUSERSITE 1 \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibraries} \
        --prefix PATH : ${
          lib.makeBinPath [
            xrandr
            xset
            xauth
            xorg-server
            pulseaudio
            procps
          ]
        }
    done
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME="$TMPDIR"
    "$out/bin/selkies" --help > /dev/null
    # --help can succeed even when optional native modules fail to load. Check
    # the actual screen/audio encoders and the ctypes-loaded keyboard library.
    env PYTHONPATH="$out/lib/python3.12/site-packages" \
      LD_LIBRARY_PATH=${lib.makeLibraryPath runtimeLibraries} \
      ${python312.interpreter} - <<'PY'
    import pcmflux
    import pixelflux
    from importlib.resources import files
    from selkies import input_handler
    assert input_handler.libxkb is not None
    assert files("selkies.selkies_web").joinpath("index.html").is_file()
    PY
    runHook postInstallCheck
  '';

  meta = {
    description = "Browser remote desktop with software video encoding, audio, and relative pointer input";
    homepage = "https://github.com/selkies-project/selkies";
    license = lib.licenses.mpl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "selkies";
    platforms = [ "x86_64-linux" ];
  };
})
