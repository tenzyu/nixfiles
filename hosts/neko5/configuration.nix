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
      "discord"
      "discord-ptb"
      "obsidian"
      "osu-lazer-bin"
      "prismlauncher"
      "cursor"
      "parsec-bin"
    ];

  hardware.opentabletdriver.enable = true;
  nixpkgs.config.permittedInsecurePackages = [
    ### opentabletdriver {{{
    "dotnet-sdk-6.0.428"
    "dotnet-sdk-wrapped-6.0.428"
    "dotnet-runtime-6.0.36"
    ### }}}
  ];

  nixpkgs.overlays = [
    (import ../../lib/overlays/unstable.nix {inherit inputs;})
    (import ../../lib/overlays/wayland.nix)
  ];

  imports = [
    ### chore {{{
    inputs.catppuccin.nixosModules.catppuccin
    ### }}}

    ../../system/programs/cloudflare-warp
    ../../system/programs/udiskie
  ];


  environment.stub-ld.enable = true;

  environment.systemPackages = with pkgs; [
    tailscale
  ];
  services.tailscale.enable = true;

  services.libinput.enable = true; # use touchpad
  services.logind.lidSwitch = "ignore";

  services.create_ap = {
    enable = true;
    settings = {
      INTERNET_IFACE = "eno2";
      WIFI_IFACE = "wlo1";
      SSID = "neko5";
      PASSPHRASE = "sw123456i"; # TODO: hash
    };
  };
}
