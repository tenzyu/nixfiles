{inputs, self, system, vm}: let
  pkgs = inputs.nixpkgs.legacyPackages.${system};
  inherit (pkgs) lib;
  # Use the pinned upstream image builders, not external mutable image aliases.
  releases = import "${inputs.nixpkgs}/nixos/release.nix" {
    configuration = {lib, pkgs, ...}: {
      documentation.enable = lib.mkForce false;
      documentation.nixos.enable = lib.mkForce false;
      system.installer.channel.enable = lib.mkForce false;
      virtualisation.incus.package = pkgs.incus;
      users.users.developer = {
        isNormalUser = true;
        uid = 1234;
      };
      environment.etc."compute-fixture/index.html".text = "compute-host-fixture";
      systemd.services.fixture-http = {
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          User = "developer";
          ExecStart = "${pkgs.python3}/bin/python3 -m http.server 8080 --directory /etc/compute-fixture";
        };
      };
      networking.firewall.allowedTCPPorts = [8080];
    };
  };
  metadata = if vm
    then "${releases.incusVirtualMachineImageMeta.${system}}/*/*.tar.xz"
    else "${releases.incusContainerMeta.${system}}/tarball/nixos-image-lxc-*-${system}.tar.xz";
  image = if vm
    then "${releases.incusVirtualMachineImage.${system}}/nixos.qcow2"
    else "${releases.incusContainerImage.${system}}/nixos-lxc-image-${system}.squashfs";
  # Test-only single-vCPU guests remove one nested-SMP variable while
  # preserving real KVM and two simultaneous guests. These are fixture sizes only.
  # Controlled mitigation, not a proven root-cause fix.
  vmFlag = lib.optionalString vm " --vm -c security.secureboot=false -c limits.memory=2048MiB -c limits.cpu=1";
in pkgs.testers.runNixOSTest {
  name = if vm then "compute-host-vm" else "compute-host-container";
  qemu.forceAccel = true;
  nodes.machine = {
    imports = [
      self.modules.nixos.incus
      ({lib, ...}: {
        options.local.features.incus.enable = lib.mkEnableOption "Incus fixture";
      })
    ];
    local.features.incus.enable = true;
    virtualisation = {
      cores = 4;
      # The nested QEMU process and image reads must not traverse the
      # outer test driver's 9p Nix store. Native block-backed EROFS store.
      useNixStoreImage = vm;
      writableStore = true;
      memorySize = if vm then 7168 else 4096;
      diskSize = 24 * 1024;
    };
    users.users.agent = {
      isNormalUser = true;
      uid = 1000;
    };
    environment.systemPackages = [pkgs.curl pkgs.jq pkgs.util-linux];
    # Co-resident native service should not be restarted by lab operations.
    systemd.services.incumbent = {
      wantedBy = ["multi-user.target"];
      serviceConfig.ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
    };
  };
  # The driver is native Python, with only immutable fixture inputs from Nix.
  testScript = ''
    import json
    spec = json.loads(${builtins.toJSON (builtins.toJSON {
      inherit vm metadata image vmFlag;
    })})
  '' + builtins.readFile ./compute-host-test.py;
}
