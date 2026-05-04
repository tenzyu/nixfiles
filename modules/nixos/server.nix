{
  config,
  lib,
  ...
}: let
  inherit (config.me) username;
in {
  flake.modules.nixos.server = {pkgs, ...}: {
    local.pkgs.useUnstable = true;

    environment.stub-ld.enable = true;
    programs.nix-ld.enable = true;

    services.tailscale.enable = true;
    networking.resolvconf.extraConfig = ''
      name_server_blacklist=172.16.0.1
    '';
    boot.kernel.sysctl."net.ipv6.conf.all.disable_ipv6" = 1;
    boot.kernel.sysctl."net.ipv6.conf.default.disable_ipv6" = 1;

    users.users.${username}.extraGroups = ["docker"];
    virtualisation.docker = {
      enable = true;
      rootless = {
        enable = true;
        setSocketVariable = true;
      };
    };

    services.qemuGuest.enable = true;

    boot.loader.grub.enable = true;
    boot.loader.grub.device = "/dev/sda";
    boot.loader.grub.useOSProber = true;
    boot.kernelPackages = pkgs.linuxPackages_latest;

    networking.networkmanager.enable = true;

    i18n.extraLocaleSettings = lib.mkDefault {
      LC_ADDRESS = "ja_JP.UTF-8";
      LC_IDENTIFICATION = "ja_JP.UTF-8";
      LC_MEASUREMENT = "ja_JP.UTF-8";
      LC_MONETARY = "ja_JP.UTF-8";
      LC_NAME = "ja_JP.UTF-8";
      LC_NUMERIC = "ja_JP.UTF-8";
      LC_PAPER = "ja_JP.UTF-8";
      LC_TELEPHONE = "ja_JP.UTF-8";
      LC_TIME = "ja_JP.UTF-8";
    };

    services.xserver.xkb = lib.mkDefault {
      layout = "us";
      variant = "";
    };

    fonts = {
      enableDefaultPackages = lib.mkDefault true;
      packages = with pkgs; [
        fira-code
        fira-code-symbols
        nerd-fonts.fira-code
        font-awesome
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-color-emoji
      ];
    };
  };
}
