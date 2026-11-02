{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
}:
stdenvNoCC.mkDerivation {
  pname = "splitcast-measurement";
  version = "0.1.0";
  src = ../../scripts/splitcast;
  dontBuild = true;
  nativeBuildInputs = [makeWrapper];
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/splitcast-measurement" "$out/bin"
    cp perf.py conditions.example.json "$out/lib/splitcast-measurement/"
    makeWrapper ${python3}/bin/python "$out/bin/splitcast-measurement" \
      --add-flags "$out/lib/splitcast-measurement/perf.py"
    runHook postInstall
  '';
  meta = {
    description = "Standalone read-only SplitCast performance measurement tools";
    mainProgram = "splitcast-measurement";
    platforms = lib.platforms.linux;
  };
}
