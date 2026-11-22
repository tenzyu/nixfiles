{
  inputs,
  config,
  ...
}: let
  authority = config.flake.modules.homeManager.home-authority;
in {
  perSystem = {pkgs, ...}: let
    witness = ../../../assets/home-authority/seal-acceptance.py;
    transitionProbe = ../../../assets/home-authority/transition-probes.py;
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
      # A second generation/reboot may re-run this oneshot. Accept only the
      # already-sealed, single-authority topology; never silently reseed.
      if [ ! -e "$source" ] && [ ! -L "$source" ] && [ -f "$target/incumbent" ]; then
        ${pkgs.e2fsprogs}/bin/lsattr -d "$h" | ${pkgs.gnugrep}/bin/grep -Eq '^[^ ]*i'
        exit 0
      fi
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
        environment.systemPackages = with pkgs; [coreutils util-linux python3 e2fsprogs];
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
        # The default QEMU test driver passes -no-reboot. Explicitly opt in
        # before the first boot, otherwise reboot diagnostics disconnect the
        # driver instead of observing the post-reboot policy and unit state.
        machine.start(allow_reboot=True)
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

        # Transition hazards are measured on disposable separate backing.
        # None of the destructive probes acts on the sealed fixture HOME.
        evidence["transition"] = json.loads(machine.succeed(
            "${pkgs.python3}/bin/python3 ${transitionProbe}"
        ))

        # A real privileged host actor can clear FS_IMMUTABLE_FL. Treat the
        # bypass as an explicit capability-boundary GAP, then restore the seal.
        machine.succeed("chattr -i /home/fixture")
        try:
            root_override = sample(
                "runuser -u fixture -- sh -c 'printf bypass > /home/fixture/.blocked'"
            )
            evidence["privileged_boundary"]["clear_immutable_then_user_create"] = root_override
            evidence["privileged_boundary"]["bypass_visible"] = sample(
                "test -f /home/fixture/.blocked && "
                "grep -Fxq bypass /home/fixture/.blocked"
            )
        finally:
            machine.succeed("rm -f /home/fixture/.blocked")
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
        # Keep the diagnostic evidence even if reboot cannot reconnect.
        # The prior independent syscall oracle was already required to pass.
        try:
            machine.reboot()
            machine.wait_for_unit("multi-user.target", timeout=120)
            evidence["lifecycle"]["reboot_transport"] = "reconnected"
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
            # Repeat the full independent direct-syscall matrix after a real
            # restart. A boot with no immutable flag must NOT appear healthy.
            code, stdout = machine.execute(
                "runuser -u fixture -- ${pkgs.python3}/bin/python3 ${witness} unwrapped",
                timeout=90,
            )
            if code != 0:
                evidence["lifecycle"]["after_reboot"]["direct_probes_error"] = {
                    "exit_code": code, "output": stdout[-1800:]
                }
            else:
                evidence["lifecycle"]["after_reboot"]["direct_probes"] = json.loads(stdout)
        except Exception as exc:
            evidence["lifecycle"]["reboot_transport"] = "BLOCKED"
            evidence["lifecycle"]["reboot_error"] = type(exc).__name__ + ": " + str(exc)[-900:]
            evidence["lifecycle"].setdefault("after_reboot", {})

        # A passing command exit code does not imply a healthy systemd unit,
        # nor does a pre-existing link prove a successful generation switch.
        def ok(item):
            return item.get("exit_code") == 0

        def unit_ok(item):
            return ok(item) and "Result=success" in item.get("output", "")

        lifecycle = evidence["lifecycle"]
        upgraded = lifecycle["after_upgrade"]
        rolled_back = lifecycle["after_rollback"]
        generation_ok = (
            ok(lifecycle["upgrade_switch"])
            and ok(upgraded["new_link_present"])
            and unit_ok(upgraded["home_manager_unit"])
            and ok(lifecycle["rollback_switch"])
            and ok(rolled_back["baseline_link"])
        )
        boot = lifecycle["after_reboot"]
        syscalls = boot.get("direct_probes", [])
        syscalls_ok = (
            len(syscalls) == 7
            and all(
                p.get("result") == ("allowed" if p.get("label") == "canonical-writer" else "denied")
                for p in syscalls
            )
        )
        reboot_ok = (
            lifecycle.get("reboot_transport") == "reconnected"
            and all(ok(boot.get(k, {})) for k in ("canonical_data", "canonical_writable", "legacy_absent"))
            and "i" in boot.get("seal", {}).get("output", "").split(" ", 1)[0]
            and all(unit_ok(boot.get(k, {})) for k in ("held_fd_service", "home_manager_unit", "seal_unit"))
            and syscalls_ok
        )
        evidence["readiness"] = {
            "vm_stale_fd_and_namespace": "PASS",
            "transition_writer_exclusion": "BLOCKED: deterministic unwrapped interposition creates split-brain",
            "two_generation_managed_links": "PASS" if generation_ok else "BLOCKED",
            "privileged_physical_root": "BLOCKED: privileged actor demonstrated immutable-flag override",
            "reboot_services": "PASS" if reboot_ok else "BLOCKED",
            "production_enforce": "BLOCKED",
            "untested_outside_vm": [
                "neko5/neko7 physical filesystems and mount topology",
                "real graphical/T3/Codex/Docker clients and daemon inheritance",
                "host administrator policy and storage snapshots",
                "other filesystems and remote storage",
            ],
        }
        # Nix test scripts run with /build as CWD; writing there is NOT the
        # output derivation. Explicitly put the JSON in $out for CI artifacts.
        import os
        from pathlib import Path
        output_dir = Path(os.environ["out"])
        output_dir.mkdir(parents=True, exist_ok=True)
        artifact = output_dir / "home-authority-evidence.json"
        artifact.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        assert artifact.is_file() and artifact.stat().st_size > 512
        print("HOME_AUTHORITY_EVIDENCE_BEGIN")
        print(json.dumps(evidence, indent=2, sort_keys=True))
        print("HOME_AUTHORITY_EVIDENCE_END")
        print("HOME_AUTHORITY_EVIDENCE_ARTIFACT=" + str(artifact.resolve()))
      '';
    };
  };
}
