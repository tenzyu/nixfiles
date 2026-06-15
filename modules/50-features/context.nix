{lib, ...}: {
  flake.modules.homeManager.context = {
    options.local.hm.context = lib.mkOption {
      type = lib.types.enum ["nixos" "standalone"];
      default = "standalone";
      description = "Whether this Home Manager evaluation is embedded in NixOS or standalone.";
    };
  };
}
