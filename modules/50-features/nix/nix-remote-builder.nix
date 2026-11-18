{...}: {
  flake.modules.nixos.nix-remote-builder = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.nix-remote-builder.enable {
      users.groups.nixbuilder = {};
      users.users.nixbuilder = {
        isSystemUser = true;
        group = "nixbuilder";
        useDefaultShell = true;
        # ssh-ng needs a trusted remote daemon account. This *one key*
        # may only start the Nix stdio daemon: no arbitrary SSH shell,
        # forwarding, agent, X11, PTY or user rc.
        openssh.authorizedKeys.keys = [
          "restrict,command=\"${config.nix.package}/bin/nix-daemon --stdio\" ${lib.removeSuffix "\n" (builtins.readFile ./neko5-nixbuilder.pub)}"
        ];
      };
      nix.settings = {
        # Required by ssh-ng remote builds per the Nix distributed-build
        # manual. Restrict access at the authorized key; do not drop trust
        # without independently proving the distributed build path.
        trusted-users = ["nixbuilder"];
        max-jobs = 2;
        cores = 6;
      };
    };
  };
}
