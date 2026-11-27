{inputs, self, ...}: {
  perSystem = {system, lib, ...}: let
    pkgs = inputs.nixpkgs.legacyPackages.${system};
    assets = ../../assets/remote-execution-mcp;
    packages = import (assets + "/packages.nix") {inherit pkgs;};
    guest = import (assets + "/guest.nix");
    release = import "${inputs.nixpkgs}/nixos/release.nix" {
      configuration = {lib, pkgs, ...}: {
        imports = [guest];
        system.stateVersion = "26.05";
        documentation.enable = lib.mkForce false;
        documentation.nixos.enable = lib.mkForce false;
        system.installer.channel.enable = false;
        users.users.root.initialHashedPassword = lib.mkForce "!";
        virtualisation.incus.package = pkgs.incus;
        services.remote-execution-mcp = {
          enable = true;
          listenAddress = "0.0.0.0";
        };
      };
    };
    image = pkgs.runCommand "remote-execution-mcp-incus-container" {} ''
      mkdir -p "$out"
      set -- ${release.incusContainerMeta.${system}}/tarball/nixos-image-lxc-*-${system}.tar.xz
      test "$#" = 1
      test -f "$1"
      ln -s "$1" "$out/metadata.tar.xz"
      ln -s ${release.incusContainerImage.${system}}/nixos-lxc-image-${system}.squashfs "$out/rootfs.squashfs"
    '';
  in lib.mkIf (system == "x86_64-linux") {
    packages = {
      remote-execution-mcp-desktop-commander = packages.desktopCommander;
      remote-execution-mcp-supergateway = packages.supergateway;
      remote-execution-mcp-container = image;
    };
    checks.remote-execution-mcp = import ../10-foundations/_internal/remote-execution-mcp-test.nix {
      inherit inputs self system image packages;
    };
  };
}
