{nixpkgs, system, name, module, extraModules ? []}: let
  pkgs = nixpkgs.legacyPackages.${system};
  guest = nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      "${nixpkgs}/nixos/maintainers/scripts/incus/incus-virtual-machine-image.nix"
      ({lib, ...}: {
        networking.hostName = "neko7-${name}";
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
      })
      module
    ] ++ extraModules;
  };
in {
  "neko7-${name}-system" = guest.config.system.build.toplevel;
  "neko7-${name}-image" = pkgs.runCommand "${name}-incus-image" {} ''
    mkdir -p "$out"
    ln -s ${guest.config.system.build.qemuImage}/nixos.qcow2 "$out/nixos.qcow2"
    set -- ${guest.config.system.build.metadata}/*/*.tar.xz
    test "$#" = 1
    test -f "$1"
    ln -s "$1" "$out/metadata.tar.xz"
  '';
}
