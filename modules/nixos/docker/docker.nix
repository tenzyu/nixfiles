{ inputs, ... }: {
  flake.modules.nixos.docker = {
    virtualisation.docker.enable = true;

    imports = with inputs.self.modules.nixos; [
      # extensions and modifications to the parent
      dockerAutoPrune
      dockerOnBoot
      dockerRootless
      dockerUser
    ];
  };
}
