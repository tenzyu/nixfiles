{lib}: {
  # Derive paths without introducing NixOS options or bypassing their merge
  # priorities. This also allows data (/srv) to be separated from service HOME.
  mkGameDirectories = spec: let
    validPart = builtins.match "[a-z][a-z0-9-]*" spec.key != null;
    validAbsolute = path:
      lib.hasPrefix "/" path
      && path != "/"
      && !(lib.hasSuffix "/" path)
      && !(lib.hasInfix "//" path)
      && !(lib.hasInfix "/../" path)
      && !(lib.hasSuffix "/.." path)
      && !(lib.hasInfix "/./" path)
      && !(lib.hasSuffix "/." path)
      && !(lib.hasPrefix "/nix/store/" path);
    home = spec.home;
    gameDir = spec.gameDir or "${home}/${spec.key}";
    secretsDir = spec.secretsDir or "${home}/secrets";
    stateDir = spec.stateDir or "${home}/.state";
  in
    assert lib.assertMsg validPart "game layout key must match [a-z][a-z0-9-]*";
    assert lib.assertMsg (lib.all validAbsolute [home gameDir secretsDir stateDir])
      "game layout paths must be normalized absolute paths outside /nix/store";
    {
      inherit home gameDir secretsDir stateDir;
      serverDir = "${gameDir}/server";
      backupsDir = "${gameDir}/backups";
      tailscaleDir = "${stateDir}/tailscale";
    };

  # The same static service account is declared on the host and inside a
  # non-user-namespaced NixOS container. Separate paths from UID/GID ownership.
  mkStaticServiceAccount = pkgs: spec: {
    users.groups.${spec.user}.gid = spec.gid;
    users.users.${spec.user} = {
      isNormalUser = true;
      uid = spec.uid;
      group = spec.user;
      home = spec.home;
      createHome = true;
      shell = pkgs.bashInteractive;
      hashedPassword = "!";
      description = "${spec.containerName} service account";
    };
  };
}
