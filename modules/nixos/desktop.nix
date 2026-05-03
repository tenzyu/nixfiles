{
  config,
  inputs,
  lib,
  ...
}: let
  unstableOverlay = final: prev: {
    unstable = import inputs.nixpkgs-unstable {
      inherit (final.stdenv.hostPlatform) system;
      inherit (final) config;
    };
  };
  waylandOverlay = self: super: {
    obsidian = super.obsidian.override {
      commandLineArgs = "--enable-wayland-ime";
    };
  };
in {
  flake.modules.nixos.desktop = {pkgs, ...}: {
    nixpkgs.config.allowUnfreePredicate = pkg:
      builtins.elem (lib.getName pkg) [
        "discord"
        "discord-ptb"
        "obsidian"
        "osu-lazer-bin"
        "prismlauncher"
        "cursor"
        "parsec-bin"
        "antigravity"
        "claude-code"
        "windsurf"
      ];

    nixpkgs.config.permittedInsecurePackages = [
      "dotnet-sdk-6.0.428"
      "dotnet-sdk-wrapped-6.0.428"
      "dotnet-runtime-6.0.36"
    ];

    nixpkgs.overlays = [
      unstableOverlay
      waylandOverlay
    ];

    imports = [
      inputs.catppuccin.nixosModules.catppuccin
      config.flake.modules.nixos.udiskie
    ];

    programs.hyprland = {
      enable = true;
      withUWSM = true;
      package = pkgs.unstable.hyprland;
      portalPackage = pkgs.unstable.xdg-desktop-portal-hyprland;
    };
    programs.hyprlock.enable = true;

    hardware.opentabletdriver.enable = true;
    environment.stub-ld.enable = true;

    services.tailscale.enable = true;
    services.libinput.enable = true;
    services.logind.settings.Login.HandleLidSwitch = "suspend";

    boot.loader.systemd-boot.enable = lib.mkDefault true;
    boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

    networking.networkmanager.enable = lib.mkDefault true;

    services.pipewire = {
      enable = lib.mkDefault true;
      pulse.enable = lib.mkDefault true;
    };

    services.blueman.enable = lib.mkDefault true;
    hardware.bluetooth = {
      enable = lib.mkDefault true;
      powerOnBoot = lib.mkDefault true;
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

    environment.sessionVariables = {
      NIXOS_OZONE_WL = "1";
      MOZ_ENABLE_WAYLAND = "1";
      QT_QPA_PLATFORM = "wayland";
      QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
      GDK_BACKEND = "wayland";
      WLR_NO_HARDWARE_CURSORS = "1";
      XDG_SESSION_TYPE = "wayland";
      XDG_CURRENT_DESKTOP = "Hyprland";
    };

    i18n.inputMethod = {
      enable = lib.mkDefault true;
      type = lib.mkDefault "fcitx5";
      fcitx5.waylandFrontend = lib.mkDefault true;
      fcitx5.addons = [
        pkgs.fcitx5-mozc-ut
      ];
    };
  };
}
