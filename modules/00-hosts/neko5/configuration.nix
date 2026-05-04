{
  cross,
  homeManager,
  nixos,
  ...
}: {
  configurations.nixos.neko5.module = {
    imports = [
      nixos.nix
      nixos.primaryUser
      nixos.homeManagerUser
      nixos.zsh
      nixos.time
      nixos.ssh
      nixos.locale
      nixos.systemState
      nixos.kernelLatest
      nixos.neko5Hardware
      nixos.unstablePackages
      nixos.llmAgents
      nixos.udiskie
      nixos.hyprlock
      nixos.openTabletDriver
      nixos.stubLd
      nixos.tailscale
      nixos.laptopInput
      nixos.systemdBoot
      nixos.networkManager
      nixos.pipewire
      nixos.bluetooth
      nixos.fonts
      nixos.waylandSession
      nixos.fcitx5
      (cross.user "tenzyu" (
        (with cross.modules; [
          parsec
          discord
          prismlauncher
          codex
          gemini-cli
          antigravity
          obsidian
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
          ncdu
          helvum
          unstable.anki-bin
          unstable.gh
        ];
      })
    ];
  };
}
