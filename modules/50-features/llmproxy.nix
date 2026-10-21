{
  flake.modules.homeManager.llmproxy = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.llmproxy.enable {
      xdg.configFile."llmproxy" = {
        source = ../../assets/llmproxy;
        recursive = true;
      };
    };
  };
}
