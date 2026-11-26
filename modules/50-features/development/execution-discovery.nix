{...}: {
  flake.modules.nixos.execution-discovery = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.execution-discovery.enable {
      # Stable discoverable contract; all dynamic inventory remains with
      # native managers. No daemon, tool RPC, scheduler or per-repo adapter.
      environment.systemPackages = [
        (pkgs.writeShellScriptBin "neko7-capabilities" ''
          export PATH=${lib.makeBinPath [pkgs.coreutils pkgs.jq]}:$PATH
          exec ${pkgs.bash}/bin/bash ${./_internal/execution-discovery.sh} "$@"
        '')
      ];
      environment.etc."neko7/execution.md".source = ./_internal/execution.md;
      environment.sessionVariables.NEKO7_EXECUTION_GUIDE = "/etc/neko7/execution.md";
    };
  };
}
