{...}: {
  flake.modules.nixos.incus = {
    config,
    lib,
    pkgs,
    ...
  }: let
    # Separate operator-owned services from disposable agent environments.
    # Incus owns instance state; NixOS owns only the substrate and bootstrap.
    bridge = name: address: {
      inherit name;
      type = "bridge";
      config = {
        "ipv4.address" = address;
        "ipv4.nat" = "true";
        "ipv6.address" = "none";
      };
    };
    profile = project: network: {
      inherit project;
      name = "default";
      config = lib.optionalAttrs (project == "lab") {
        "limits.cpu" = "2";
        "limits.memory" = "2GiB";
      };
      devices = {
        root = {
          type = "disk";
          pool = "default";
          path = "/";
        };
        eth0 = {
          type = "nic";
          name = "eth0";
          inherit network;
        };
      };
    };
  in {
    config = lib.mkIf config.local.features.incus.enable {
      # The NixOS Incus module requires nftables with the host firewall.
      networking.nftables.enable = true;
      environment.systemPackages = [pkgs.just pkgs.jq pkgs.util-linux];
      systemd.tmpfiles.rules = ["d /run/lock/neko7-instances 0770 root wheel -"];
      networking.firewall.interfaces = lib.genAttrs ["incusbr0" "incuslab0"] (_: {
        allowedTCPPorts = [53];
        allowedUDPPorts = [53 67];
      });

      virtualisation.incus = {
        enable = true;
        # The default LTS line is not the version verified for the restricted
        # client authorization fix GHSA-5c64-j5m6-8433. Use the pinned 7.6+ line.
        package = pkgs.incus;
        ui.enable = true;
        softDaemonRestart = true;
        preseed = {
          config."core.https_address" = "127.0.0.1:8443";
          storage_pools = [{
            name = "default";
            driver = "dir";
          }];
          networks = [
            (bridge "incusbr0" "10.77.40.1/24")
            (bridge "incuslab0" "10.77.41.1/24")
          ];
          projects = [{
            name = "lab";
            description = "Restricted general-purpose execution environments";
            config = {
              "features.images" = "true";
              "features.profiles" = "true";
              "features.storage.volumes" = "true";
              "features.storage.buckets" = "true";
              "features.networks.zones" = "true";
              # Bridge networks live in the operator project. The restricted
              # client can only attach to the designated lab bridge.
              "features.networks" = "false";
              # Initial admission budget, not an adaptive resource governor.
              # Counts allocated resources, including stopped instances.
              "limits.instances" = "8";
              "limits.virtual-machines" = "0"; # VM admission deferred pending lifecycle evidence
              "limits.cpu" = "8";
              "limits.memory" = "8GiB";
              "restricted" = "true";
              "restricted.networks.access" = "incuslab0";
              "restricted.devices.disk" = "managed";
              "restricted.devices.nic" = "managed";
              "restricted.devices.gpu" = "block";
              "restricted.devices.proxy" = "block";
              "restricted.containers.nesting" = "block";
              "restricted.virtual-machines.lowlevel" = "block";
            };
          }];
          profiles = [
            (profile "default" "incusbr0")
            (profile "lab" "incuslab0")
          ];
        };
      };

      assertions = [{
        assertion = lib.versionAtLeast config.virtualisation.incus.package.version "7.6.0";
        message = "Restricted Incus access requires the 7.6.0 authorization fix (GHSA-5c64-j5m6-8433) or newer.";
      }];
      # Deliberately do not grant incus-admin or incus group membership.
      # incus-user's automatic per-UID project allows host HOME bind mounts;
      # an operator enrolls a restricted TLS client instead.
    };
  };
}
