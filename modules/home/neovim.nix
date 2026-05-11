{inputs, ...}: {
  flake.modules.homeManager.neovim = {
    config,
    pkgs,
    ...
  }: {
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

    xdg.enable = true;

    xdg.dataFile."applications/lazyvim.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=LazyVim
      GenericName=Text Editor
      Exec=${pkgs.kitty}/bin/kitty -e ${config.programs.neovim.finalPackage}/bin/nvim %F
      Terminal=false
      Categories=Utility;TextEditor;
      MimeType=text/plain;
      StartupNotify=false
    '';

    xdg.mimeApps = {
      enable = true;
      associations.added."text/plain" = ["lazyvim.desktop"];
      defaultApplications."text/plain" = ["lazyvim.desktop"];
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
        nixd
        alejandra
      ];
    };
  };
}
