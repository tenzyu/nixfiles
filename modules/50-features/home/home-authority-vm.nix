{
  inputs,
  config,
  ...
}: let
  homeAuthority = config.flake.modules.homeManager.home-authority;
in {
  perSystem = {pkgs, ...}: let
    probe = ../../../assets/home-authority/test-vm.py;
    user = "fixture";
    home = "/home/${user}";
    writer = pkgs.writeShellScript "home-authority-fixture-writer" ''
      set -eu
      printf 'service\n' > ${home}/.local/share/authority/from-service
    '';
  in {
    # A diagnostic VM: negative controls explicitly show why observing
    # or bind-mounting a single view is not the full authority contract.
    checks.home-authority-vm = pkgs.testers.runNixOSTest {
      name = "home-authority-boundaries";
      requiredFeatures.kvm = false;
      nodes.machine = {pkgs, ...}: {
        imports = [inputs.home-manager.nixosModules.home-manager];
        boot.tmp.useTmpfs = false;
        virtualisation.memorySize = 1536;
        system.stateVersion = "26.05";

        users.users.${user} = {
          isNormalUser = true;
          uid = 1000;
          home = home;
          createHome = true;
        };

        environment.systemPackages = with pkgs; [
          coreutils
          e2fsprogs
          util-linux
          python3
        ];

        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          sharedModules = [homeAuthority];
          users.${user} = {
            home.username = user;
            home.homeDirectory = home;
            home.stateVersion = "26.05";
            programs.home-manager.enable = true;
            xdg.enable = true;
            local.homeAuthority = {
              enable = true;
              root.forbidden = [".legacy"];
              states.example = {
                legacy = ".legacy";
                canonical = "${home}/.local/share/authority";
                mode = "observe";
              };
            };
          };
        };

        systemd.services.home-authority-fixture-writer = {
          description = "Fixture: systemd writer sharing canonical state";
          serviceConfig = {
            Type = "oneshot";
            User = user;
            ExecStart = writer;
          };
        };
      };

      testScript = ''
        machine.start()
        machine.wait_for_unit("home-manager-fixture.service")
        machine.succeed("${pkgs.python3}/bin/python3 ${probe} audit")

        # A dual-populated state must be reported, not merged or overwritten.
        machine.succeed("${pkgs.python3}/bin/python3 ${probe} seed-collision")
        machine.succeed("systemctl restart home-manager-fixture.service")
        machine.succeed("${pkgs.python3}/bin/python3 ${probe} check-collision")

        # Successful pathname alias, then deliberate stale-FD split-brain.
        machine.succeed("${pkgs.python3}/bin/python3 ${probe} bind")

        # Negative control: sandboxing only one namespace is insufficient.
        machine.succeed("${pkgs.python3}/bin/python3 ${probe} readonly-view")

        # A physical directory immutable bit does not revoke open file FDs.
        machine.succeed("${pkgs.python3}/bin/python3 ${probe} immutable")
      '';
    };
  };
}
