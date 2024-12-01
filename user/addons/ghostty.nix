{
  inputs,
  config,
  system,
  ...
}: {
  home.packages = [
    (config.lib.nixGL.wrap inputs.ghostty.packages.${system}.default)
  ];
}
