{inputs, self, ...}: {
  perSystem = {pkgs, config, system, ...}: let
    inherit (inputs.nixpkgs) lib;
    hosts = self.nixosConfigurations;
    desktop = (import ../../scripts/desktop/evaluate-desktop.nix {flake = self;}).result;
    # Parse only for inspection: fromTOML rejects derivation string contexts.
    # The actual Home Manager file retains its runtime store references.
    jay = builtins.fromTOML (builtins.unsafeDiscardStringContext desktop.jay);
    primary = hosts.neko5.config;
    server = hosts.neko7.config;
    hm = primary.home-manager.users.tenzyu;
    keys = jay.shortcuts;
    startup = map (action: action.exec) jay.on-graphics-initialized;
    privileged = action: builtins.isAttrs action && (action.privileged or false);
    # These are local integration contracts, not tests of upstream Jay.
    startupContract = builtins.length startup == 3
      && builtins.isList (builtins.elemAt startup 0)
      && lib.hasSuffix "/bin/dbus-update-activation-environment" (builtins.head (builtins.elemAt startup 0))
      && (builtins.elemAt startup 1) == {prog = "cclip-start"; args = []; privileged = true;}
      && lib.hasSuffix "/bin/fcitx5" (builtins.elemAt startup 2).prog
      && (builtins.elemAt startup 2).args == ["-r"]
      && privileged (builtins.elemAt startup 2)
      && !((builtins.elemAt startup 2) ? tag)
      && keys.logo-ctrl-i.exec == builtins.elemAt startup 2
      && builtins.length (builtins.filter privileged startup) == 2
      && (jay.clients or []) == [];
    shortcutPrivileges = lib.attrNames (lib.filterAttrs (_: action:
      builtins.isAttrs action && privileged (action.exec or null)) keys)
      == ["Print" "logo-ctrl-i" "logo-shift-s"];
    workspaceContract = jay.workspace-display-order == "sorted"
      && jay.actions.next-workspace == "$workspace-2"
      && jay.actions.previous-workspace == "$workspace-10"
      && keys.logo-Tab == "$next-workspace" && keys.logo-shift-Tab == "$previous-workspace"
      && lib.all (n: let
        name = toString n;
        key = toString (if n == 10 then 0 else n);
        action = "$workspace-${name}";
        next = toString (if n == 10 then 1 else n + 1);
        prev = toString (if n == 1 then 10 else n - 1);
      in keys."logo-${key}" == action
        && keys."logo-shift-${key}" == [{type = "move-to-workspace"; inherit name;} action]
        && jay.actions."workspace-${name}" == [
          {type = "show-workspace"; inherit name;}
          {type = "define-action"; name = "next-workspace"; action = "$workspace-${next}";}
          {type = "define-action"; name = "previous-workspace"; action = "$workspace-${prev}";}
        ]) (lib.range 1 10);
    packages = hm.home.packages;
    package = name: lib.findFirst (p: lib.getName p == name)
      (throw "Missing selected desktop package: ${name}") packages;
    profilePasses = p: lib.all (name: p.${name}) [
      "profile" "launcher" "legacyDesktopDisabled" "systemPolicy" "identity"
      "audio" "realtime" "hardwareAudio" "desktopPackages"
    ] && lib.hasSuffix ".drv" p.drv;
    checks = {
      host-evaluation = lib.all (host: lib.hasSuffix ".drv" host.config.system.build.toplevel.drvPath)
        (lib.attrValues hosts);
      state-versions = lib.all (host: hosts.${host}.config.system.stateVersion == "26.05") ["neko5" "neko7"];
      remote-builder-trust = lib.all (host: !hosts.${host}.config.nix.settings.accept-flake-config) ["neko5" "neko7"]
        && builtins.length server.users.users.nixbuilder.openssh.authorizedKeys.keys == 1
        && lib.all (key: lib.hasPrefix "restrict,command=" key && lib.hasInfix "/bin/nix-daemon --stdio" key && lib.hasInfix "ssh-ed25519 " key)
          server.users.users.nixbuilder.openssh.authorizedKeys.keys
        && lib.elem "nixbuilder" server.nix.settings.trusted-users
        && lib.any (m: m.protocol == "ssh-ng" && m.sshUser == "nixbuilder") primary.nix.buildMachines;
      neko5-desktop = desktop.onlyProbe && desktop.audioIsolated && desktop.presentationCcsScope
        && profilePasses desktop.primary && profilePasses desktop.probe;
      presentation = jay.direct-scanout && jay.tearing.mode == "variant3"
        && (builtins.head jay.outputs).tearing.mode == "variant2"
        && (builtins.head jay.outputs).match.connector == "eDP-1"
        && (builtins.head jay.outputs).mode == {width = 1366; height = 768;}
        && (builtins.head jay.outputs).scale == 1.0
        && jay.vrr.mode == "never" && !jay.xwayland.enabled;
      clipboard-ime = desktop.alacrittyOsc52 == "OnlyCopy" && desktop.herdrReusesStock
        && keys.logo-v.exec == ["cclip-picker"]
        && lib.hasSuffix "/bin/fcitx5-remote" (builtins.head keys.logo-i.exec)
        && keys.logo-ctrl-i.exec.privileged
        && keys.logo-shift-s.exec.privileged && keys.Print.exec.privileged
        && builtins.tail keys.logo-i.exec == ["-t"]
        && startupContract && shortcutPrivileges;
      workspace-cycle = workspaceContract;
      associations = desktop.skinAssociation == ["org.kde.ark.desktop"]
        && desktop.fileAssociation == ["dev.fileman.Files.desktop"];
    };
    failures = lib.attrNames (lib.filterAttrs (_: passed: !passed) checks);
    fastChecks = [
      "framework" "host-policy" "desktop-packages" "docs" "clipboard"
      "t3-serve" "opencode-direnv" "parsec-activation"
      "rtk-rewrites" "steam-gaming" "safety-python" "safety-shell"
      "game-backup-minecraft" "splitcast-cache-cli"
    ];
  in {
    checks = lib.optionalAttrs (system == "x86_64-linux") {
      host-policy =
        assert lib.assertMsg (failures == []) ("Host contract violations: " + builtins.toJSON failures);
        pkgs.runCommand "host-policy" {} "touch $out";

      # Validate the packaged artifacts, not mocked upstream implementation.
      desktop-packages = pkgs.runCommand "desktop-packages" {} ''
        test -x ${package "cclip"}/bin/cclip
        test -x ${package "cclip"}/bin/cclipd
        test -x ${package "fileman"}/bin/fileman
        test -f ${package "fileman"}/share/applications/dev.fileman.Files.desktop
        test -x ${package "cclip-start"}/bin/cclip-start
        test -x ${package "cclip-picker"}/bin/cclip-picker
        test -x ${package "jay-rofi-actions"}/bin/jay-rofi-actions
        service=${package "mako"}/share/dbus-1/services/org.freedesktop.Notifications.service
        test -f "$service"
        grep -Fx 'Name=org.freedesktop.Notifications' "$service"
        grep -Fx 'SystemdService=mako.service' "$service"
        grep -Fx 'Type=dbus' ${package "mako"}/lib/systemd/user/mako.service
        grep -Fx 'BusName=org.freedesktop.Notifications' ${package "mako"}/lib/systemd/user/mako.service
        touch "$out"
      '';

      clipboard = pkgs.runCommand "clipboard-integration" {
        nativeBuildInputs = [pkgs.python3 pkgs.bash pkgs.coreutils pkgs.util-linux];
      } ''
        cp -r ${../../scripts/desktop} desktop
        chmod -R u+w desktop
        # Fixture subprocesses use /bin/bash; the sandbox does not provide it.
        substituteInPlace desktop/test-clipboard-integration.py --replace-fail /bin/bash ${pkgs.bash}/bin/bash
        python3 desktop/test-clipboard-integration.py
        touch "$out"
      '';

      t3-serve = pkgs.runCommand "t3-serve-contract" {
        nativeBuildInputs = [pkgs.bash pkgs.coreutils pkgs.jq];
      } ''
        cp ${../../scripts/test-t3code-tailnet.sh} test.sh
        chmod u+w test.sh
        substituteInPlace test.sh --replace-fail /usr/bin/env ${pkgs.coreutils}/bin/env
        bash test.sh ${pkgs.writeText "t3-serve-restore" server.systemd.services.t3code-tailnet.script}
        touch "$out"
      '';

      # Only the offline argument boundary; signed remote verification is on demand.
      splitcast-cache-cli = pkgs.runCommand "splitcast-cache-cli" {nativeBuildInputs = [pkgs.bash];} ''
        script=${../../scripts/ci/audit-splitcast-cache.sh}
        bash -n "$script"
        bash "$script" --help
        status=0
        bash "$script" --unknown-option || status=$?
        test "$status" = 2
        status=0
        bash "$script" --strict extra || status=$?
        test "$status" = 2
        touch "$out"
      '';

      # The pinned nixpkgs package owns Markdown parsing and local URL resolution.
      docs = pkgs.runCommand "documentation-links" {
        nativeBuildInputs = [pkgs.lychee];
        # Lychee initializes its TLS client even for an offline link check.
        SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      } ''
        cd ${self}
        lychee --offline --root-dir "$PWD" README.md AGENTS.md MEMORY.md ROADMAP.md 'docs/**/*.md'
        touch "$out"
      '';

      # Nix tracks actual derivation inputs and substitution; no source-path
      # selector, test-of-selector or branch-name-dependent policy.
      validation = pkgs.linkFarm "nixfiles-validation" (map (name: {
        inherit name;
        path = config.checks.${name};
      }) fastChecks);
    };
  };
}
