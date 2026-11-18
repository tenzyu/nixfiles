{
  configurations.nixos.nestedhost.module = {
    local = {
      context = {
        hostName = "nestedhost";
      };
      features = {
        beta.enable = true;
      };
    };
  };
}
