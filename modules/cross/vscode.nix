{
  local.cross.definitions.vscode = {
    ambient = [
      {
        policy.pkgs.allowUnfreeNames = ["vscode"];
      }
    ];

    home.packages = pkgs: [
      pkgs.vscode
    ];
  };
}
