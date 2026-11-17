{
  flake.modules.homeManager.nix-tools = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.nix-tools.enable {
      home.sessionVariables = lib.mkIf (config.local.context.flakePath != null) {
        NH_OS_FLAKE = config.local.context.flakePath;
      };

      home.packages = with pkgs; [
        nh
        jq
        jqp
        zip
        ncdu
        crosspipe
      ];
    };
  };
}
