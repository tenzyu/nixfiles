{inputs, ...}: {
  flake.modules.homeManager.neovim = {pkgs, ...}: {
    programs.neovim = {
      enable = true;

      defaultEditor = true;
      viAlias = true;
      vimAlias = true;

      extraPackages = with pkgs; [
        fd
        ripgrep
        stylua
        lua-language-server
        typescript-language-server
        vscode-langservers-extracted
      ];
    };

    imports = [inputs.lazyvim.homeManagerModules.default];
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
        unstable.nixd
        alejandra
      ];
    };
  };
}
