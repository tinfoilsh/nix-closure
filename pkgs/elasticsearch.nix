{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  coreutils,
  gnugrep,
  zlib,
  alsa-lib,
  fontconfig,
  freetype,
  libX11,
  libXext,
  libXi,
  libXrender,
  libXtst,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "elasticsearch";
  version = "9.5.5";

  src = fetchurl {
    url = "https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${finalAttrs.version}-linux-x86_64.tar.gz";
    hash = "sha512-Nr9daJf67aN0OEHfrs42UzC7QYgPkH5MRZWJZN0oA2F9UDy6ZumWhhJImc/5RMmDsBouCOrr2PVMJtsCv3Cc7Q==";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [
    stdenv.cc.cc.lib
    zlib
    alsa-lib
    fontconfig
    freetype
    libX11
    libXext
    libXi
    libXrender
    libXtst
  ];
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/elasticsearch $out/bin
    cp -r bin config jdk lib modules plugins LICENSE.txt NOTICE.txt $out/share/elasticsearch/
    for program in $out/share/elasticsearch/bin/*; do
      case "$(basename "$program")" in
        elasticsearch-env*|elasticsearch-cli) continue ;;
      esac
      makeWrapper "$program" "$out/bin/$(basename "$program")" \
        --prefix PATH : ${
          lib.makeBinPath [
            coreutils
            gnugrep
          ]
        }
    done
    runHook postInstall
  '';

  meta = {
    description = "Distributed RESTful search and analytics engine";
    homepage = "https://www.elastic.co/elasticsearch";
    license = lib.licenses.elastic20;
    sourceProvenance = [
      lib.sourceTypes.binaryNativeCode
      lib.sourceTypes.binaryBytecode
    ];
    mainProgram = "elasticsearch";
    platforms = [ "x86_64-linux" ];
  };
})
