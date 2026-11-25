{...}: {
  flake.modules.nixos.execution-discovery = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.execution-discovery.enable {
      # Stable discoverable contract; all dynamic inventory remains with
      # native managers. No daemon, tool RPC, scheduler or per-repo adapter.
      environment.etc."neko7/execution.md".source = ./_internal/execution.md;
      environment.sessionVariables.NEKO7_EXECUTION_GUIDE = "/etc/neko7/execution.md";
    };
  };
}
