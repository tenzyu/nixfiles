(self: super: {
  obsidian = super.obsidian.override {
    commandLineArgs = "--enable-wayland-ime";
  };
})
