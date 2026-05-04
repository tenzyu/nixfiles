{
  config,
  inputs,
  ...
}: let
  inherit (config.flake.modules) homeManager nixos;
  inherit (config.flake.lib.cross) user;
  cross = config.flake.lib.cross.modules;
in {
  configurations.nixos.neko5.module = {pkgs, ...}: {
    boot.kernelPackages = pkgs.linuxPackages_latest;
    policy.pkgs.allowUnfreeNames = [
      "obsidian"
      "parsec-bin"
      "discord"
      "prismlauncher"
    ];

    imports = [
      nixos.pkgsRuntime
      nixos.common
      nixos.desktop
      nixos.neko5Hardware
      (user "tenzyu" [
        cross.osu-lazer
        cross.catppuccin
        cross.hyprland
        homeManager.common
        homeManager.packagesCommon
        homeManager.packagesDesktop
        homeManager.zsh
        homeManager.btop
        homeManager.fastfetch
        homeManager.firefox
        homeManager.fzf
        homeManager.git
        homeManager.hyprpaper
        homeManager.kitty
        homeManager.neovim
        homeManager.rofi
        homeManager.starship
        homeManager.tmux
        homeManager.waybar
        homeManager.wlogout
        homeManager.yazi
        homeManager.zedEditor
        homeManager.zoxide
      ])
      {
        networking.hostName = "neko5";

        home-manager.users."tenzyu" = {
          home.packages = with pkgs; [
            nh
            jq
            jqp
            lazygit
            zip
            obsidian
            parsec-bin
            unstable.anki-bin
            unstable.discord
            unstable.gh
            unstable.prismlauncher
            inputs.llm-agents.packages.x86_64-linux.codex
            inputs.llm-agents.packages.x86_64-linux.gemini-cli
            inputs.antigravity-nix.packages.x86_64-linux.default
          ];
        };
      }
    ];
  };
}
