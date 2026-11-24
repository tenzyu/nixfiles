{
  # Jay is the normal generation; Gamescope is a separate native DRM probe.
  configurations.nixos.neko5.module.imports = [
    ({...}: {
      specialisation.neko5-gamescope.configuration = {lib, ...}: {
        local.features.jay.enable = lib.mkForce false;
        local.users.tenzyu.features.jay.enable = lib.mkForce false;
        local.features.gamescope.enable = true;
        # Independent native DRM reference; do not inherit the Jay-specific workaround.
        home-manager.users.tenzyu.local.osuLazer.disableIntelCcs = lib.mkForce false;
      };
    })
  ];
}
