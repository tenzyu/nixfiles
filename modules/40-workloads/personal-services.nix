{inputs, ...}: {
  perSystem = {system, lib, ...}: let
    pkgs = inputs.nixpkgs.legacyPackages.${system};
    # Independently deployable VM releases using upstream NixOS Incus image
    # modules. No dependency from the neko7 host generation to these closures.
    common = {lib, ...}: {
      imports = ["${inputs.nixpkgs}/nixos/maintainers/scripts/incus/incus-virtual-machine-image.nix"];
      system.stateVersion = "26.05";
      documentation.enable = lib.mkForce false;
      documentation.nixos.enable = lib.mkForce false;
      system.installer.channel.enable = false;
      users.users.root.initialHashedPassword = lib.mkForce "!";
      services.openssh.enable = lib.mkForce false;
      services.getty.helpLine = lib.mkForce "Manage this guest with the Incus agent.";
      services.tailscale = {enable = true; openFirewall = false;};
      networking.firewall.enable = true;
      environment.systemPackages = [pkgs.curl];
    };
    machine = name: module: inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [common {networking.hostName = name;} module];
    };
    syncthing = machine "neko7-syncthing" ./_internal/syncthing.nix;
    immich = machine "neko7-immich" ./_internal/immich.nix;
    image = name: guest: pkgs.runCommand "${name}-incus-image" {} ''
      mkdir -p "$out"
      ln -s ${guest.config.system.build.qemuImage}/nixos.qcow2 "$out/nixos.qcow2"
      set -- ${guest.config.system.build.metadata}/*/*.tar.xz
      test "$#" = 1
      test -f "$1"
      ln -s "$1" "$out/metadata.tar.xz"
    '';
  in {
    packages = lib.optionalAttrs (system == "x86_64-linux") {
      neko7-syncthing-system = syncthing.config.system.build.toplevel;
      neko7-syncthing-image = image "syncthing" syncthing;
      neko7-immich-system = immich.config.system.build.toplevel;
      neko7-immich-image = image "immich" immich;
    };
  };
}
