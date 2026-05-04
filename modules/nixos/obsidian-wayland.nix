{
  flake.modules.nixos.obsidianWayland = {
    nixpkgs.overlays = [
      (self: super: {
        obsidian = super.obsidian.override {
          commandLineArgs = "--enable-wayland-ime";
        };
      })
    ];
  };
}
