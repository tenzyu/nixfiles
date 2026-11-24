{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  git,
  wayland,
  wayland-scanner,
  sqlite,
  xxhash,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "cclip";
  version = "3.3.1";

  src = fetchFromGitHub {
    owner = "heather7283";
    repo = "cclip";
    rev = "4286de1c8407ccba51060764e82c6b425b4ca3dd";
    hash = "sha256-rjDCYag0aG9mZuwzWNS5z/CzeEtpdjc9iMypKqIZK60=";
  };

  nativeBuildInputs = [meson ninja pkg-config git wayland-scanner];
  buildInputs = [wayland sqlite xxhash];

  meta = {
    description = "Event-driven Wayland clipboard history manager";
    homepage = "https://github.com/heather7283/cclip";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
    mainProgram = "cclip";
  };
})
