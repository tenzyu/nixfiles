{feature, ...}: {
  configurations.nixos.neko6.module = {
    imports = [
      (feature.system {
        stateVersion = "26.05";
        features = {
          wsl-integration = true;
          nix = true;
          time = true;
          locale = true;
          passwordless-sudo = true;
          ssh = true;
          ssh-debug = true;
          empty-nix-access-tokens = true;
          nix-ld = true;
          docker-rootful = true;
          docker-on-boot = true;
          docker-auto-prune = true;
        };
      })

      (feature.users {
        tenzyu = {
          isAdmin = true;
          homeStateVersion = "26.05";
          fullName = "tenzyu";
          email = "tenzyu.on@gmail.com";

          features = {
            tenzyu-cli = true;
            wsl-default-user = true;
            docker-user-access = true;
          };
          imports = [{home.sessionVariables.NIXOS_OZONE_WL = "1";}];
        };
      })
    ];
  };
}
