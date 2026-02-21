let
  inherit (import ../../lib/default.nix) nixosModules;
in
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
        "antigravity"
        "claude-code"
        "windsurf"
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
      (import nixosModules.overlays.unstable {inherit inputs;})
      (import nixosModules.overlays.wayland)
    ];

    imports = [
      ### chore {{{
      inputs.catppuccin.nixosModules.catppuccin
      ### }}}

      nixosModules.programs.udiskie
      nixosModules.programs.hyprland
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
