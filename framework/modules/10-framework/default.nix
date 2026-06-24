{frameworkRoot}: {inputs, ...}: {
  _module.args.frameworkRoot = frameworkRoot;

  imports = [
    ./flake-modules.nix
    ./configurations.nix
    ./helpers.nix
    ./formatter.nix
    ./systems.nix
    ./cli-apps.nix
  ];
}
