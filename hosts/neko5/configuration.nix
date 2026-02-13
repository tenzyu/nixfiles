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
    ../../system/programs/udiskie
    ../../system/programs/hyprland
  ];

  environment.stub-ld.enable = true;

  services.tailscale.enable = true;
  services.libinput.enable = true; # use touchpad

  services.logind.settings = {
    Login = {
      HandleLidSwitch = "suspend";
    };
  };
}
