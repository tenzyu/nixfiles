{
  local.cross.definitions.parsec = {
    ambient = [
      {
        policy.pkgs.allowUnfreeNames = ["parsec-bin"];
      }
    ];

    home.packages = pkgs: [
      pkgs.parsec-bin
    ];
  };
}
