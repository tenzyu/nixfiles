{...}: {
  flake.modules.nixos.nix-remote-builder = {config, lib, ...}: {
    config = lib.mkIf config.local.features.nix-remote-builder.enable {
      users.groups.nixbuilder = {};
      users.users.nixbuilder = {
        isSystemUser = true;
        group = "nixbuilder";
        useDefaultShell = true;
        openssh.authorizedKeys.keyFiles = [./neko5-nixbuilder.pub];
      };
      nix.settings = {
        trusted-users = ["nixbuilder"];
        max-jobs = 2;
        cores = 6;
      };
    };
  };
}
