{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  versionCheckHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "envoy";
  version = "1.36.10";

  src = fetchurl {
    url = "https://github.com/envoyproxy/envoy/releases/download/v${finalAttrs.version}/envoy-${finalAttrs.version}-linux-x86_64";
    hash = "sha256-3A/XYTcb470tAIIudh7nteiR9dz6bnC2Ix+Fik9vtm4=";
  };
  dontUnpack = true;
  dontBuild = true;
  dontStrip = true;
  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/envoy
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  meta = {
    description = "Edge and service proxy";
    homepage = "https://www.envoyproxy.io/";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "envoy";
    platforms = [ "x86_64-linux" ];
  };
})
