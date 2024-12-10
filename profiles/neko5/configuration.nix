{
  inputs,
  pkgs,
  config,
  overlays,
  lib,
  ...
}: {
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "cloudflare-warp"
      "discord-ptb"
      "obsidian"
      "osu-lazer-bin"
    ];

  nixpkgs.overlays = [
    (import ../../lib/overlays/unstable.nix {inherit inputs;})
    (import ../../lib/overlays/wayland.nix)
  ];

  imports = [
    ### chore {{{
    inputs.catppuccin.nixosModules.catppuccin
    ../../lib/nix.nix
    ### }}}

    ../../system/programs/cloudflare-warp
    ../../system/programs/keyd
    ../../system/programs/udiskie
    ../../system/programs/hyprland

    # ../../system/programs/kmonad
  ];

  users.users.tenzyu = {
    isNormalUser = true;
    shell = pkgs.zsh;
    packages = with pkgs; []; # NOTE: prefer using home-manager
    extraGroups = [
      "wheel"
      "input"
      "uinput"
    ];
  };

  programs.zsh = {
    enable = true; # home-manager は /etc/shells に入るわけではないので.
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  services.pipewire = {
    enable = true;
    pulse.enable = true;
  };
  services.blueman.enable = true;
  services.libinput.enable = true; # use touchpad
  services.openssh.enable = true;
  services.create_ap = {
    enable = true;
    settings = {
      INTERNET_IFACE = "eno2";
      WIFI_IFACE = "wlo1";
      SSID = "neko5";
      PASSPHRASE = "sw123456i"; # TODO: hash
    };
  };
  services.logind.lidSwitch = "ignore";

  environment.systemPackages = with pkgs; [
    neovim
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  time.timeZone = "Asia/Tokyo";

  networking.hostName = "neko5"; # Define your hostname.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental = true;
      };
    };
  };
  hardware.opentabletdriver.enable = true;
  nixpkgs.config.permittedInsecurePackages = [
    ### opentabletdriver {{{
    "dotnet-sdk-6.0.428"
    "dotnet-sdk-wrapped-6.0.428"
    "dotnet-runtime-6.0.36"
    ### }}}
  ];

  i18n.defaultLocale = "en_US.UTF-8";
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.waylandFrontend = true;
    fcitx5.addons = [
      pkgs.fcitx5-mozc-ut
    ];
  };

  console = {
    font = "Lat2-Terminus16";
    # keyMap = "us";
    # useXkbConfig = true; # use xkb.options in tty.
  };

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "24.11"; # Did you read the comment?
}
