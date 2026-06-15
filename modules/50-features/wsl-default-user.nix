{
  flake.effects.wsl-default-user = {
    requires = ["wsl-integration"];

    user = {user, ...}: {
      config = {
        wsl.defaultUser = user.name;
      };
    };
  };
}
