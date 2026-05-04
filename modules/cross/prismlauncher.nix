{
  local.cross.definitions.prismlauncher = {
    ambient = [
      {
        local.pkgs.useUnstable = true;
      }
      {
        policy.pkgs.allowUnfreeNames = ["prismlauncher"];
      }
    ];

    home.packages = pkgs: [
      pkgs.unstable.prismlauncher
    ];
  };
}
