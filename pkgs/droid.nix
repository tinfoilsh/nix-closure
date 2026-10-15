# Factory publishes droid as a prebuilt bun binary inside a per-platform npm
# package; the `droid` package is only a postinstall that picks one.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  versionCheckHook,
  writableTmpDirAsHomeHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "droid";
  version = "0.213.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@factory/cli-linux-x64/-/cli-linux-x64-${finalAttrs.version}.tgz";
    hash = "sha256-KAqNbtol8cqQM6jwHEdLNcKvmBQ/FK4a9uVOVBjVVG4=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];
  # Stripping removes Bun's embedded application; the executable then runs Bun.
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/droid $out/bin/droid
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    writableTmpDirAsHomeHook
    versionCheckHook
  ];
  versionCheckKeepEnvironment = [ "HOME" ];
  versionCheckProgramArg = "--version";

  meta = {
    description = "Factory Droid CLI, an AI software engineering agent";
    homepage = "https://factory.ai";
    license = lib.licenses.unfree;
    mainProgram = "droid";
    platforms = [ "x86_64-linux" ];
  };
})
