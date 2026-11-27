{inputs, self, ...}: {
  perSystem = {system, lib, ...}: let
    host = self.nixosConfigurations.neko7.config;
    home = host.home-manager.users.tenzyu;
    incus = host.virtualisation.incus;
    labProjects = lib.filter (project: project.name == "lab") incus.preseed.projects;
    t3Exec = home.systemd.user.services.t3code-neko7.Service.ExecStart;
    withContract = name: predicates: test: let
      failures = lib.attrNames (lib.filterAttrs (_: passed: !passed) predicates);
    in
      assert lib.assertMsg (failures == []) (name + " host contract violations: " + builtins.toJSON failures);
      test;
    deploymentGraph = {
      host = host.system.build.toplevel.drvPath;
      artifacts = lib.genAttrs [
        "neko7-minecraft-system"
        "neko7-t3-runtime"
        "neko7-splitcast-runtime"
      ] (name: self.packages.${system}.${name}.drvPath);
    };
  in {
    checks = lib.optionalAttrs (system == "x86_64-linux") {
      multi-machine-lab = import ./_internal/multi-machine-lab-test.nix {
        inherit inputs system;
      };
      platform-services = import ./_internal/platform-services-test.nix {
        inherit inputs self system;
      };
      workload-lifecycle = withContract "Workload lifecycle" {
        minecraft-profile = toString host.containers.neko7-mc.path == "/nix/var/nix/profiles/system";
        t3-profile = builtins.isList t3Exec && t3Exec != []
          && lib.all (arg: builtins.isString arg && lib.hasInfix "/nix/profiles/t3-runtime/bin/t3" arg) t3Exec;
        splitcast-profile = home.local.features.splitcast-production-profile.enable;
        splitcast-legacy-disabled = !home.services.splitcast.enable;
        activation-guards = host.system.preSwitchChecks ? minecraft-workload-profile
          && host.system.preSwitchChecks ? neko7-workload-profiles;
      } ((import ./_internal/workload-lifecycle-test.nix {inherit inputs system;}) // {
        inherit deploymentGraph;
      });
      tailnet-ingress = withContract "Tailnet ingress" {
        enabled = host.local.features.tailnet-ingress.enable;
        no-forward-ports = host.networking.nat.forwardPorts == [];
        nftables-family = host.networking.nftables.tables.tailnet_ingress.family == "inet";
      } (import ./_internal/tailnet-ingress-test.nix {inherit inputs self system;});
      compute-host-container = withContract "Incus integration" {
        enabled = incus.enable;
        package-version = builtins.isString incus.package.version;
        package-derivation = lib.hasSuffix ".drv" incus.package.drvPath;
        private-listener = incus.preseed.config."core.https_address" == "127.0.0.1:8443";
        restricted-lab = labProjects != [] && lib.all (project: project.config.restricted == "true") labProjects;
        unprivileged-user = !lib.any (group: lib.elem group ["incus-admin" "incus"]) host.users.users.tenzyu.extraGroups;
        minecraft-container = host.containers ? neko7-mc;
        host-derivation = lib.hasSuffix ".drv" host.system.build.toplevel.drvPath;
      } (import ./_internal/compute-host-test.nix {
        inherit inputs self system;
        vm = false;
      });
    };
  };
}
