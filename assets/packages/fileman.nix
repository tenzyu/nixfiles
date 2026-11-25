{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  wrapGAppsHook4,
  gtk4,
  libadwaita,
  libarchive,
  glib,
  cairo,
  pango,
  gdk-pixbuf,
  graphene,
  harfbuzz,
  pigz,
  ffmpeg,
  poppler-utils,
  rclone,
  fuse3,
  ntfs3g,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "fileman";
  version = "0.5.2";

  src = fetchurl {
    url = "https://github.com/0znio/fileman/releases/download/v${finalAttrs.version}/fileman-${finalAttrs.version}-x86_64-linux.tar.gz";
    sha256 = "fc26ad2acdff21cb45ac94b81ee025fffe0b04cfc2518f8fc76f35155451d733";
  };

  nativeBuildInputs = [autoPatchelfHook wrapGAppsHook4];
  buildInputs = [
    stdenv.cc.cc.lib
    gtk4
    libadwaita
    libarchive
    glib
    cairo
    pango
    gdk-pixbuf
    graphene
    harfbuzz
  ];

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 fileman "$out/bin/fileman"
    install -Dm644 share/applications/dev.fileman.Files.desktop "$out/share/applications/dev.fileman.Files.desktop"
    substituteInPlace "$out/share/applications/dev.fileman.Files.desktop" \
      --replace-fail 'Exec=fileman ' "Exec=$out/bin/fileman "
    cp -r share/icons "$out/share/"
    # Keep the existing GTK FileChooser portal; do not install/activate
    # Fileman's optional portal backend from the release archive.
    runHook postInstall
  '';

  preFixup = ''
    gappsWrapperArgs+=(--prefix PATH : "${lib.makeBinPath [(lib.getBin libarchive) pigz ffmpeg poppler-utils rclone fuse3 ntfs3g]}")
  '';

  meta = {
    description = "GTK4 file manager (official release binary)";
    homepage = "https://github.com/0znio/fileman";
    license = lib.licenses.mit;
    platforms = ["x86_64-linux"];
    mainProgram = "fileman";
    sourceProvenance = [lib.sourceTypes.binaryNativeCode];
  };
})
