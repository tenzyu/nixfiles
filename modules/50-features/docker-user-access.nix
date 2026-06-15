{
  flake.effects.docker-user-access = {
    user = {user, ...}: {
      config = {
        users.users.${user.name}.extraGroups = ["docker"];
      };
    };
  };
}
