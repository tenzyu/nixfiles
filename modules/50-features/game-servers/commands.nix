{...}: {
  flake.modules.nixos.game-server-containers = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.game-server-containers.enable {
      environment.shellAliases.g = "game";
      environment.systemPackages = [
        (pkgs.writeShellApplication {
          name = "game";
          runtimeInputs = with pkgs; [bash coreutils gnugrep gnutar gzip sudo systemd];
          text = builtins.readFile ./_internal/game.sh;
        })
      ];
    };
  };
}
