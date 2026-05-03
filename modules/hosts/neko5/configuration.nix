{
  config,
  inputs,
  ...
}: let
  inherit (config.me) username;
  inherit (config.flake.modules) homeManager nixos;
in {
  configurations.nixos.neko5.module = {pkgs, ...}: {
    imports = [
      nixos.common
      nixos.desktop
      nixos.neko5Hardware
      {
        networking.hostName = "neko5";

        home-manager.users.${username} = {
          imports = [
            homeManager.common
            homeManager.packagesCommon
            homeManager.packagesDesktop
            homeManager.zsh
            homeManager.btop
            homeManager.fastfetch
            homeManager.fzf
            homeManager.git
            homeManager.hyprland
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
            inputs.catppuccin.homeModules.catppuccin
          ];
          catppuccin.enable = true;
          home.packages = with pkgs; [
            nh
            jq
            jqp
            lazygit
            zip
            obsidian
            parsec-bin
            unstable.anki-bin
            unstable.claude-code
            unstable.code-cursor
            unstable.discord
            unstable.gemini-cli
            unstable.gh
            unstable.osu-lazer-bin
            unstable.prismlauncher
            unstable.windsurf
            inputs.antigravity-nix.packages.x86_64-linux.default
            inputs.codex-cli-nix.packages.x86_64-linux.default
          ];
        };
      }
    ];
  };
}
