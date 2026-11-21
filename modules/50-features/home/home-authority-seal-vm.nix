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
      '';
    };
  };
}
