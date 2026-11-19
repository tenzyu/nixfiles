{...}: {
  flake.modules.nixos.t3code-browser = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.t3code-browser.enable {
      # Chromium Headless Shell is a foreign ELF binary. The NixOS host's
      # nix-ld loader must resolve its runtime libraries from the Nix store.
      programs.nix-ld.libraries = with pkgs; [
        alsa-lib
        at-spi2-core
        dbus
        expat
        glib
        libgbm
        libx11
        libxcb
        libxcomposite
        libxdamage
        libxext
        libxfixes
        libxkbcommon
        libxrandr
        nspr
        nss
        systemd
      ];
    };
  };
}
