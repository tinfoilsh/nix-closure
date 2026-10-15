{
  lib,
  stdenvNoCC,
  fetchurl,
  versionCheckHook,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "qdrant";
  version = "1.18.2";

  src = fetchurl {
    url = "https://github.com/qdrant/qdrant/releases/download/v${finalAttrs.version}/qdrant-x86_64-unknown-linux-musl.tar.gz";
    hash = "sha256-QKavRPikllYMnSNStrKgragWqkjQeBxo9gJYLmezrqA=";
  };
  sourceRoot = ".";
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 qdrant $out/bin/qdrant
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  meta = {
    description = "Vector search engine";
    homepage = "https://qdrant.tech/";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "qdrant";
    platforms = [ "x86_64-linux" ];
  };
})
