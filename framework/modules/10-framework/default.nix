{frameworkRoot}: {inputs, ...}: {
  _module.args.frameworkRoot = frameworkRoot;

  imports = [
    ./flake-modules.nix
    ./configurations.nix
    ./helpers.nix
    ./cli-apps.nix
  ];
}
