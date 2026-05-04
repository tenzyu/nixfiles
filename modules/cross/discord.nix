{
  local.cross.definitions.discord = {
    ambient = [
      {
        local.pkgs.useUnstable = true;
      }
      {
        policy.pkgs.allowUnfreeNames = ["discord"];
      }
    ];

    home.packages = pkgs: [
      pkgs.unstable.discord
    ];
  };
}
