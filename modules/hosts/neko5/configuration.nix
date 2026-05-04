{
  cross,
  homeManager,
  nixos,
  ...
}: {
  configurations.nixos.neko5.module = {
    imports = [
      nixos.kernelLatest
      nixos.common
      nixos.desktop
      nixos.neko5Hardware
      (cross.user "tenzyu" (
        (with cross.modules; [
          obsidian
          parsec
          discord
          prismlauncher
          codex
          gemini-cli
          antigravity
          osu-lazer
          catppuccin
          hyprland
        ])
        ++ (with homeManager; [
          common
          packagesCommon
          packagesDesktop
          zsh
          btop
          fastfetch
          firefox
          fzf
          git
          hyprpaper
          kitty
          neovim
          rofi
          starship
          tmux
          waybar
          wlogout
          yazi
          zedEditor
          zoxide
        ])
      ))
      ({pkgs, ...}: {
        home-manager.users."tenzyu".home.packages = with pkgs; [
          nh
          jq
          jqp
          lazygit
          zip
          unstable.anki-bin
          unstable.gh
        ];
      })
    ];
  };
}
