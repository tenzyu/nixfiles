{
  local.cross.definitions.obsidian = {
    ambient = [
      {
        policy.pkgs.allowUnfreeNames = ["obsidian"];
      }
    ];

    home.packages = pkgs: [
      pkgs.obsidian
    ];
  };
}
