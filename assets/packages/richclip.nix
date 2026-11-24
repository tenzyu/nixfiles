{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  wayland,
  sqlite,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "richclip";
  version = "0.1.3";

  src = fetchurl {
    url = "https://github.com/dstoc/richclip/releases/download/richclip-v${finalAttrs.version}/richclip-richclip-v${finalAttrs.version}-x86_64-unknown-linux-gnu.tar.gz";
    sha256 = "63d3303c4d7fc543e7b1887607509c11aba9c89fe7f13c27b9e68a3fab4d57cd";
  };

  nativeBuildInputs = [autoPatchelfHook];
  buildInputs = [stdenv.cc.cc.lib wayland sqlite];

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 richclip "$out/bin/richclip"
    install -Dm755 richclipd "$out/bin/richclipd"
    # Do not install the optional remote image labelling worker.
    runHook postInstall
  '';

  meta = {
    description = "Multi-MIME Wayland clipboard history (official release binary)";
    homepage = "https://github.com/dstoc/richclip";
    platforms = ["x86_64-linux"];
    mainProgram = "richclip";
    sourceProvenance = [lib.sourceTypes.binaryNativeCode];
  };
})
