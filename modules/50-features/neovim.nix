{inputs, ...}: {
  flake.modules.homeManager.neovim = {
    config,
    lib,
    pkgs,
    ...
  }: {
    imports = [
      inputs.lazyvim.homeManagerModules.default
    ];

    config = lib.mkIf config.local.features.neovim.enable {
      programs.neovim = {
        enable = true;
        defaultEditor = true;
        viAlias = true;
        vimAlias = true;
      };

      programs.lazyvim = {
        enable = true;

        extras = {
          lang.nix.enable = true;

          lang.typescript = {
            enable = true;
            installDependencies = false;
            installRuntimeDependencies = false;
          };
        };

        extraPackages = with pkgs; [
          nixd
          alejandra
        ];
      };
    };
  };
}
