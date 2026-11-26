{inputs, self, system, name, image, candidate, guestMemory, stateProbe}: let
  pkgs = inputs.nixpkgs.legacyPackages.${system};
in pkgs.testers.runNixOSTest {
  name = "incus-workload-${name}";
  qemu.forceAccel = true;
  globalTimeout = 75 * 60;
  nodes.neko7 = {
    imports = [
      self.modules.nixos.incus
      ({lib, ...}: {options.local.features.incus.enable = lib.mkEnableOption "Incus fixture";})
    ];
    local.features.incus.enable = true;
    virtualisation = {
      cores = 4;
      # Native local store image instead of nested QEMU/image I/O over 9p.
      useNixStoreImage = true;
      writableStore = true;
      memorySize = 7168;
      diskSize = 48 * 1024;
      additionalPaths = [image candidate];
    };
    environment.systemPackages = [pkgs.curl pkgs.jq pkgs.just pkgs.util-linux];
  };
  # Keep the test driver in native Python; Nix supplies only immutable inputs.
  testScript = ''
    import json
    spec = json.loads(${builtins.toJSON (builtins.toJSON {
      inherit name guestMemory;
      image = toString image;
      candidate = toString candidate;
      runtimeShell = pkgs.runtimeShell;
      justfile = toString ../../../justfile;
      ops = toString ../../../tools/instance-ops.sh;
      inherit (stateProbe) seed verify;
      injectActivationFailure = name == "syncthing";
    })})
  '' + builtins.readFile ./incus-lifecycle.py;
}
