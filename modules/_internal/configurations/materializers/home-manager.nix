{
  homeFeatureOptionsModule,
  homeModuleList,
  embeddedHomeFeatures,
  enabledUsers,
}: selectedUsers: {
  config,
  lib,
  pkgs,
  helpers,
  ...
}: let
  users = enabledUsers config.local.users;
  hm = config.home-manager;
  marker = name: "home-migration/${name}";
in {
  config.environment.etc = lib.mapAttrs' (name: _:
    lib.nameValuePair (marker name) {
      source = hm.users.${name}.home.activationPackage;
    })
  users;

  config.system.preSwitchChecks = lib.mapAttrs' (name: _:
    lib.nameValuePair "home-migration-${name}" (let
      inherit (hm.users.${name}.home) homeDirectory activationPackage;
      user = lib.escapeShellArg name;
      home = lib.escapeShellArg homeDirectory;
    in ''
      generation=${activationPackage}
      if ! [ "$generation" -ef "$1/etc/${marker name}" ]; then
        echo "Home migration admission received a different candidate generation" >&2
        exit 1
      fi
      incumbent="/run/current-system/etc/${marker name}"
      uid="$(${pkgs.coreutils}/bin/id -u -- ${user})"
      gid="$(${pkgs.coreutils}/bin/id -g -- ${user})"
      account="$(${pkgs.getent}/bin/getent passwd ${user})"
      IFS=: read -r _ _ _ _ _ account_home _ <<< "$account"
      if [ "$uid" -eq 0 ] || [ "$account_home" != ${home} ]; then
        echo "Home migration admission requires the affected non-root account and matching HOME" >&2
        exit 1
      fi
      sessions=(--sessions-active)
      if roster="$(${pkgs.systemd}/bin/loginctl list-users --no-legend --no-pager)" &&
         ! ${pkgs.gawk}/bin/awk -v uid="$uid" '$1 == uid { found = 1 } END { exit !found }' <<< "$roster"; then
        sessions=()
      fi
      ${pkgs.util-linux}/bin/setpriv --reuid="$uid" --regid="$gid" --init-groups --no-new-privs \
        ${pkgs.coreutils}/bin/env -i HOME=${home} USER=${user} LC_ALL=C \
        HOME_MANAGER_BACKUP_EXT=${lib.escapeShellArg (
        if hm.backupFileExtension == null
        then ""
        else hm.backupFileExtension
      )} \
        HOME_MANAGER_BACKUP_COMMAND=${lib.escapeShellArg (
        if hm.backupCommand == null
        then ""
        else toString hm.backupCommand
      )} \
        HOME_MANAGER_BACKUP_OVERWRITE=${lib.escapeShellArg (
        if hm.overwriteBackup
        then "1"
        else ""
      )} \
        "$generation/home-layout-pre-switch" "$generation" --incumbent "$incumbent" "''${sessions[@]}"
    ''))
  users;

  config.home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";

    extraSpecialArgs = {
      inherit helpers;
    };

    sharedModules =
      [
        homeFeatureOptionsModule
      ]
      ++ homeModuleList;

    users =
      lib.mapAttrs
      (
        userName: user: {
          imports = [
            {
              local.user = {
                name = userName;
                inherit (user.context) email homeDirectory;
                stateVersion = user.context.homeStateVersion;
              };

              local.context = {
                flakePath = config.local.context.flakePath;
                hostName = config.local.context.hostName;
                nixosConfigurationName = config.local.context.nixosConfigurationName;
                homeConfigurationName = "${userName}@${config.local.context.nixosConfigurationName}";
                embeddedInNixOS = true;
              };

              # Respect host explicit false without converting implicit native false into
              # an HM false definition.
              local.features =
                embeddedHomeFeatures
                (selectedUsers.${userName}.features or {})
                user.features;

              programs.home-manager.enable = lib.mkDefault true;
              xdg.enable = lib.mkDefault true;
              home.preferXdgDirectories = lib.mkDefault true;
              home.username = lib.mkDefault userName;
              home.homeDirectory = lib.mkDefault user.context.homeDirectory;
              home.stateVersion = lib.mkDefault user.context.homeStateVersion;
            }
          ];
        }
      )
      users;
  };
}
