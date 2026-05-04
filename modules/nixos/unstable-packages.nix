{
  flake.modules.nixos.unstablePackages = {
    local.pkgs.useUnstable = true;
  };
}
