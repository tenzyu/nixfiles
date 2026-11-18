{
  configurations.nixos.testhost.module = {
    local.features = {
      beta.enable = true;
    };
    local.users.alice = {
      features = {
        bar.enable = true;
      };
    };
  };
}
