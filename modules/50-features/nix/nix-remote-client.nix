{...}: {
  flake.modules.nixos.nix-remote-client = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.nix-remote-client.enable {
      nix.distributedBuilds = true;
      nix.settings.builders-use-substitutes = true;
      nix.buildMachines = [
        {
          hostName = "neko7";
          sshUser = "nixbuilder";
          sshKey = "/root/.ssh/neko7-nixbuilder";
          protocol = "ssh-ng";
          system = "x86_64-linux";
          maxJobs = 2;
          speedFactor = 1;
          supportedFeatures = ["big-parallel"];
        }
      ];
    };
  };
}
