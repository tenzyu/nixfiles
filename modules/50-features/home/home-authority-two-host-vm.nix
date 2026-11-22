{...}: {
  perSystem = {pkgs, ...}: let
    fixtureNode = {...}: {
      system.stateVersion = "26.05";
      boot.tmp.useTmpfs = false;
      virtualisation.memorySize = 1024;
      users.users.fixture = {
        isNormalUser = true;
        uid = 1000;
        home = "/home/fixture";
        createHome = true;
      };
      environment.systemPackages = with pkgs; [coreutils e2fsprogs util-linux python3];
    };
  in {
    # Two physically independent VM disks and administrator domains.
    # This measures v1.1's HOST-INDEPENDENCE non-goal, not shared authority.
    checks.home-authority-two-host-vm = pkgs.testers.runNixOSTest {
      name = "home-authority-local-host-independence";
      requiredFeatures.kvm = false;
      nodes = {
        alpha = fixtureNode;
        beta = fixtureNode;
      };
      testScript = ''
        import json
        import os
        from pathlib import Path

        alpha.start(allow_reboot=True)
        beta.start(allow_reboot=True)
        alpha.wait_for_unit("multi-user.target")
        beta.wait_for_unit("multi-user.target")

        evidence = {
            "schema": "home-authority-v11-two-host/v1",
            "scope": "two disposable QEMU nodes with separate local storage",
            "global_agreement_required": False,
            "host_deployment": False,
            "observations": {},
        }

        def initialize(machine, identity):
            machine.succeed(
                "install -d -m 0700 -o fixture -g users /var/lib/v11-authority-state"
            )
            machine.succeed("chattr +i /home/fixture")
            machine.succeed(
                "runuser -u fixture -- sh -c "
                "'echo " + identity
                + " > /var/lib/v11-authority-state/instance; sync'"
            )
            immutable = machine.succeed("lsattr -d /home/fixture")
            assert "i" in immutable.split(" ", 1)[0]
            denied, output = machine.execute(
                "runuser -u fixture -- mkdir /home/fixture/.legacy"
            )
            assert denied != 0, ("unsealed HOME: " + output)
            assert machine.execute("test ! -e /home/fixture/.legacy")[0] == 0
            actual = machine.succeed("cat /var/lib/v11-authority-state/instance").strip()
            assert actual == identity, (identity, actual)
            return {
                "kernel": machine.succeed("uname -r").strip(),
                "filesystem": machine.succeed(
                    "findmnt -no FSTYPE,SOURCE --target /home/fixture"
                ).strip(),
                "immutable": immutable.strip(),
                "legacy_create_denied": True,
                "authority_state": actual,
            }

        evidence["observations"]["alpha"] = initialize(alpha, "alpha")
        evidence["observations"]["beta"] = initialize(beta, "beta")
        assert evidence["observations"]["alpha"]["authority_state"] != (
            evidence["observations"]["beta"]["authority_state"]
        )

        # Sudden loss of one local host does not require the other to obtain
        # a global lease or accept the failed host's state as its authority.
        alpha.crash()
        beta.succeed(
            "runuser -u fixture -- sh -c "
            "'echo beta-continues >> /var/lib/v11-authority-state/instance; sync'"
        )
        continuing = beta.succeed(
            "cat /var/lib/v11-authority-state/instance"
        ).splitlines()
        assert continuing == ["beta", "beta-continues"], continuing
        evidence["observations"]["beta_writes_during_alpha_crash"] = True

        alpha.start(allow_reboot=True)
        alpha.wait_for_unit("multi-user.target")
        after_crash = alpha.succeed(
            "cat /var/lib/v11-authority-state/instance"
        ).strip()
        assert after_crash == "alpha", after_crash
        assert "i" in alpha.succeed("lsattr -d /home/fixture").split(" ", 1)[0]
        assert alpha.execute(
            "runuser -u fixture -- mkdir /home/fixture/.legacy"
        )[0] != 0
        evidence["observations"]["alpha_fsynced_state_survived_crash"] = True
        evidence["observations"]["alpha_home_seal_survived_crash"] = True
        evidence["local_host_independence_fixture"] = "PASS"
        evidence["not_proven"] = [
            "actual neko5/neko7 runtime topology",
            "physical power-loss durability",
            "concurrent daemon and GUI applications",
            "complete nested HOME immutability",
        ]

        out = Path(os.environ["out"])
        out.mkdir(parents=True, exist_ok=True)
        report = out / "home-authority-two-host-evidence.json"
        report.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n")
        assert report.stat().st_size > 350
        print("HOME_AUTHORITY_TWO_HOST_EVIDENCE_BEGIN")
        print(json.dumps(evidence, indent=2, sort_keys=True))
        print("HOME_AUTHORITY_TWO_HOST_EVIDENCE_END")
      '';
    };
  };
}
