{
  inputs,
  config,
  ...
}: let
  authority = config.flake.modules.homeManager.home-authority;
in {
  perSystem = {pkgs, ...}: let
    witness = ../../../assets/home-authority/seal-acceptance.py;
    home = "/home/fixture";
    # VM-scoped candidate backend. This is not permitted on real hosts:
    # freezing a real HOME would break subsequent Home Manager generations.
    # The held-FD witness owns the old inode; rename preserves that inode,
    # while the physical HOME immutable flag rejects direct new entries.
    seal = pkgs.writeShellScript "home-authority-fixture-seal" ''
      set -euo pipefail
      h=${home}
      source="$h/.legacy"
      target="$h/.local/share/authority"
      if [ ! -d "$source" ] || [ -L "$source" ] ||
         [ ! -d "$target" ] || [ -L "$target" ]; then
        echo "refusing unrecognized incumbent/target topology" >&2
        exit 1
      fi

      # Fail closed on a populated competing state; never merge, copy or
      # overwrite an existing target. This fixture starts with an empty
      # target and the incumbent as the sole populated authority.
      if [ -n "$(${pkgs.findutils}/bin/find "$target" -mindepth 1 -print -quit)" ]; then
        echo "canonical target is populated; refusing to choose authority" >&2
        exit 1
      fi
      if [ "$(${pkgs.coreutils}/bin/stat -c %u "$source")" != 1000 ]; then
        echo "unexpected incumbent owner" >&2
        exit 1
      fi
      ${pkgs.coreutils}/bin/rmdir "$target"
      ${pkgs.coreutils}/bin/mv -T --no-copy --update=none-fail -- "$source" "$target"
      ${pkgs.e2fsprogs}/bin/chattr +i "$h"

      # Verify the physical filesystem, not a private mount view.
      ${pkgs.e2fsprogs}/bin/lsattr -d "$h" | ${pkgs.gnugrep}/bin/grep -Eq '^[^ ]*i'
      [ ! -e "$source" ] && [ ! -L "$source" ]
      [ -f "$target/incumbent" ]
    '';
  in {
    # Separate red acceptance gate, NOT the successful negative-control test.
    checks.home-authority-seal-vm = pkgs.testers.runNixOSTest {
      name = "home-authority-independent-seal-acceptance";
      requiredFeatures.kvm = false;
      nodes.machine = {pkgs, ...}: {
        imports = [inputs.home-manager.nixosModules.home-manager];
        boot.tmp.useTmpfs = false;
        virtualisation.memorySize = 1536;
        system.stateVersion = "26.05";
        users.users.fixture = {
          isNormalUser = true;
          uid = 1000;
          home = home;
          createHome = true;
        };
        environment.systemPackages = with pkgs; [coreutils util-linux python3];
        # Genuine second NixOS/HM generation: changing a root-level managed
        # link must NOT be mistaken for successful activation under +i.
        home-manager.users.fixture.home.file.".hm-baseline".text = "baseline\n";
        specialisation.next.configuration = {
          home-manager.users.fixture.home.file.".hm-generation-two".text = "generation-two\n";
        };


        # Sealing must happen AFTER HM has produced its generation links.
        # The witness is deliberately kept alive; it is NOT killed/closed.
        systemd.services.home-authority-fixture-seal = {
          wantedBy = ["multi-user.target"];
          requires = ["home-manager-fixture.service"];
          after = ["home-manager-fixture.service"];
          before = ["multi-user.target"];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "root";
            ExecStart = seal;
          };
        };

        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          sharedModules = [authority];
          users.fixture = {
            home.username = "fixture";
            home.homeDirectory = home;
            home.stateVersion = "26.05";
            programs.home-manager.enable = true;
            xdg.enable = true;
            local.homeAuthority = {
              enable = true;
              root.forbidden = [".legacy" ".blocked"];
              states = {
                old = {
                  legacy = ".legacy";
                  canonical = "${home}/.local/share/authority";
                };
                direct = {
                  legacy = ".blocked";
                  canonical = "${home}/.local/share/authority/blocked";
                };
              };
            };
          };
        };

        # Type=notify provides an exact pre-policy barrier: the witness MUST
        # acquire the old directory and file descriptors before HM activation.
        systemd.services.home-authority-held-fds = {
          wantedBy = ["multi-user.target"];
          before = ["home-manager-fixture.service"];
          serviceConfig = {
            Type = "notify";
            NotifyAccess = "main";
            User = "fixture";
            RuntimeDirectory = "home-authority-held-fds";
            RuntimeDirectoryMode = "0700";
            ExecStart = "${pkgs.python3}/bin/python3 ${witness} hold";
          };
        };
        systemd.services.home-manager-fixture = {
          requires = ["home-authority-held-fds.service"];
          after = ["home-authority-held-fds.service"];
        };
      };

      testScript = ''
        machine.start()
        machine.wait_for_unit("home-authority-held-fds.service")
        machine.wait_for_unit("home-manager-fixture.service")
        machine.wait_for_unit("home-authority-fixture-seal.service")
        # No inverted assertion or expected-failure escape hatch here.
        result = machine.succeed("${pkgs.python3}/bin/python3 ${witness} verify")
        print(result) # Persist the independent PASS oracle in CI logs.

        # Diagnostic evidence, separate from the immutable acceptance oracle:
        # these observations intentionally do NOT certify a host backend.
        import json
        evidence = {
            "schema": "home-authority-vm-evidence/v1",
            "scope": "disposable-single-host-VM",
            "host_deployment": False,
            "enforce_backend_production": False,
            "initial_seal_oracle": "PASS",
            "capabilities": {},
            "lifecycle": {},
            "privileged_boundary": {},
        }

        def sample(command, timeout=90):
            code, output = machine.execute(command, timeout=timeout)
            return {"exit_code": code, "output": output[-1800:]}

        evidence["capabilities"]["kernel"] = machine.succeed("uname -r").strip()
        evidence["capabilities"]["filesystem"] = machine.succeed(
            "findmnt --target /home/fixture -no FSTYPE,SOURCE,OPTIONS"
        ).strip()
        evidence["capabilities"]["mount_namespace"] = machine.succeed(
            "readlink /proc/1/ns/mnt"
        ).strip()
        evidence["capabilities"]["physical_immutable_flags"] = machine.succeed(
            "lsattr -d /home/fixture"
        ).strip()
        evidence["capabilities"]["uid_and_home_inode"] = machine.succeed(
            "stat -c '%u:%g %d:%i' /home/fixture"
        ).strip()
        evidence["capabilities"]["canonical_inode"] = machine.succeed(
            "stat -c '%u:%g %d:%i' /home/fixture/.local/share/authority"
        ).strip()
        evidence["capabilities"]["baseline_link"] = machine.succeed(
            "test -L /home/fixture/.hm-baseline && cat /home/fixture/.hm-baseline"
        ).strip()

        # A real privileged host actor can clear FS_IMMUTABLE_FL. Treat the
        # bypass as an explicit capability-boundary GAP, then restore the seal.
        machine.succeed("chattr -i /home/fixture")
        try:
            root_override = sample(
                "runuser -u fixture -- sh -c 'printf bypass > /home/fixture/.root-override'"
            )
            evidence["privileged_boundary"]["clear_immutable_then_user_create"] = root_override
            evidence["privileged_boundary"]["bypass_visible"] = sample(
                "test -f /home/fixture/.root-override && "
                "grep -Fxq bypass /home/fixture/.root-override"
            )
        finally:
            machine.succeed("rm -f /home/fixture/.root-override")
            machine.succeed("chattr +i /home/fixture")
        # Make the observable capability escape a required fact, not a SKIP.
        assert evidence["privileged_boundary"]["clear_immutable_then_user_create"]["exit_code"] == 0
        assert evidence["privileged_boundary"]["bypass_visible"]["exit_code"] == 0
        evidence["privileged_boundary"]["conclusion"] = "GAP: root with CAP_LINUX_IMMUTABLE can unseal physical HOME"

        # Genuine system-specialisation upgrade, *without* lifting the seal.
        initial_system = machine.succeed("readlink -f /run/current-system").strip()
        next_system = machine.succeed(
            "readlink -f /run/current-system/specialisation/next"
        ).strip()
        assert initial_system and next_system and initial_system != next_system
        evidence["lifecycle"]["generation_one"] = initial_system
        evidence["lifecycle"]["generation_two"] = next_system
        evidence["lifecycle"]["upgrade_switch"] = sample(
            next_system + "/bin/switch-to-configuration test", timeout=180
        )
        evidence["lifecycle"]["after_upgrade"] = {
            "new_link_present": sample("test -e /home/fixture/.hm-generation-two"),
            "home_manager_unit": sample("systemctl show -p ActiveState -p Result home-manager-fixture.service"),
            "physical_seal": sample("lsattr -d /home/fixture"),
            "canonical_writable": sample(
                "runuser -u fixture -- sh -c 'printf ok > /home/fixture/.local/share/authority/lifecycle-check'"
            ),
        }
        evidence["lifecycle"]["rollback_switch"] = sample(
            initial_system + "/bin/switch-to-configuration test", timeout=180
        )
        evidence["lifecycle"]["after_rollback"] = {
            "baseline_link": sample("test -L /home/fixture/.hm-baseline"),
            "physical_seal": sample("lsattr -d /home/fixture"),
            "legacy_still_absent": sample("test ! -e /home/fixture/.legacy"),
        }

        # Reboot should preserve data and physical policy. Observe the actual
        # services rather than faking a healthy two-generation boot.
        machine.reboot()
        machine.wait_for_unit("multi-user.target")
        evidence["lifecycle"]["after_reboot"] = {
            "seal": sample("lsattr -d /home/fixture"),
            "canonical_data": sample("grep -Fxq 'before' /home/fixture/.local/share/authority/incumbent"),
            "legacy_absent": sample("test ! -e /home/fixture/.legacy"),
            "held_fd_service": sample("systemctl show -p ActiveState -p Result home-authority-held-fds.service"),
            "home_manager_unit": sample("systemctl show -p ActiveState -p Result home-manager-fixture.service"),
            "seal_unit": sample("systemctl show -p ActiveState -p Result home-authority-fixture-seal.service"),
            "canonical_writable": sample(
                "runuser -u fixture -- sh -c 'printf postboot > /home/fixture/.local/share/authority/reboot-writer'"
            ),
        }

        # A strong result is not confused with a successful lifecycle:
        # any failed service/link remains recorded as a blocker.
        print("HOME_AUTHORITY_EVIDENCE_BEGIN")
        print(json.dumps(evidence, indent=2, sort_keys=True))
        print("HOME_AUTHORITY_EVIDENCE_END")
      '';
    };
  };
}
