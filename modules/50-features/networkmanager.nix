{
  flake.effects.networkmanager-access = {
    requires = ["networkmanager"];
    user = {user, ...}: {
      config = {
        users.users.${user.name}.extraGroups = ["networkmanager"];
      };
    };
  };

  flake.modules.nixos.networkmanager = {
    networking.networkmanager.enable = true;
    networking.nameservers = [
      "1.1.1.1"
      "1.0.0.1"
      "8.8.8.8"
      "8.8.4.4"
    ];
  };
}
