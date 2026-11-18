{
  flake.local.featurePolicies.game-server-containers.unfree = [
    "steamcmd"
    "steam"
    "steam-run"
    "steam-original"
    "steam-unwrapped"
  ];
  # Typed, opt-in cutover switch; actual service implementation remains native.
  flake.modules.nixos.game-srv = {};

  flake.modules.nixos.game-server-containers = {
    config,
    lib,
    ...
  }: {
    # Compatibility only: existing declarative callers may still select the
    # old bundle. The neko7 host now selects each game and its tooling itself.
    config = lib.mkIf config.local.features.game-server-containers.enable {
      local.features = {
        game-ark.enable = lib.mkDefault true;
        game-rust.enable = lib.mkDefault true;
        game-minecraft.enable = lib.mkDefault true;
        game-server-tools.enable = lib.mkDefault true;
      };
      networking.nat = {
        enable = true;
        externalInterface = "ens18";
      };
    };
  };
}
