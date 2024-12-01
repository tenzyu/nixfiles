{
  pkgs,
  config,
  ...
}: {
  home.file.".config/zsh/zshrc.d".source = config.lib.file.mkOutOfStoreSymlink ./zshrc;

  programs.zsh = {
    enable = true;

    dotDir = ".config/zsh";

    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    history = {
      path = "${config.xdg.stateHome}/zsh/history";
      save = 1000000;
      size = 1000000;
    };

    shellAliases = {
      c = "clear";
      q = "exit";
      shutdown = "systemctl poweroff";
      update-grub = "sudo grub-mkconfig -o /boot/grub/grub.cfg";

      v = "${config.home.sessionVariables.EDITOR}";
      vi = "${config.home.sessionVariables.EDITOR}";
      vim = "${config.home.sessionVariables.EDITOR}";
      n = "${config.home.sessionVariables.EDITOR}";

      nf = "fastfetch";
      ls = "eza --color=always --long --git --no-filesize --icons=always --no-time --no-user --no-permissions";
      ll = "eza -al --icons=always";
      lt = "eza -a --tree --level=3 --icons=always";
      wifi = "nmtui";
      zed = "zeditor";
      wget = "wget --hsts-file='${config.xdg.dataHome}/wget-hsts'";
      grep = "rg";
      cd = "z";
      moe = "moree";
      fk = "thefuck";
      tk = "thefuck";
    };

    # TODO: fzf-git をいい感じにする.
    initExtra = ''
      for f in ${config.xdg.configHome}/zsh/zshrc.d/*; do
          if [ ! -d $f ] ;then
              source $f
          fi
      done
      source ~/.config/zsh/zshrc.d/externals/fzf-git.sh

      if [[ $(tty) == *"pts"* ]]; then
          fastfetch --config examples/13
      else
          echo
          if [ -f /bin/hyprctl ]; then
              echo "Start Hyprland with command Hyprland"
          fi
      fi
    '';
  };
}
