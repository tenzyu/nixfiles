# Generated sources are ordinary hashed inputs, not imported Nix build outputs.
# A changed upstream derivation falls back to the original package.
{lib, upstream}: let
  manifest = builtins.fromJSON (builtins.readFile ./manifest.json);
  current = lib.filterAttrs (name: receipt:
    builtins.hasAttr name upstream && upstream.${name}.drvPath == receipt.drvPath
  ) manifest;
in
  upstream // lib.mapAttrs (name: receipt: builtins.path {
    path = ./data + "/${name}";
    inherit name;
    sha256 = receipt.narHash;
  }) current
