{
  flake.modules.homeManager.nix-tools = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.nix-tools.enable {
      home.packages = with pkgs; [
        jq
        jqp
        zip
        ncdu
        crosspipe
      ];
    };
  };
}
