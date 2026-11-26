# Supporting subdomain: one workload definition produces its immutable release
# artifacts and a distinct, otherwise identical acceptance candidate.
{inputs, self, nixpkgs, system, name, module, guestMemory, stateProbe, injectActivationFailure ? false}: let
  image = extraModules: import ./incus-image.nix {
    inherit nixpkgs system name module extraModules;
  };
  packages = image [];
  candidate = (image [{environment.etc."neko7/fixture-release".text = "candidate";}])."neko7-${name}-system";
in {
  inherit packages;
  lifecycle = import ./incus-lifecycle.nix {
    inherit inputs self system name candidate guestMemory stateProbe injectActivationFailure;
    image = packages."neko7-${name}-image";
  };
}
